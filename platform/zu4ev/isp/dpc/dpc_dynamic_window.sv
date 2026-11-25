`timescale 1ns/1ps
// Two-pixel 3x3 window over four rotating synchronous line banks. The input
// side writes one WIDTH/2 x 20 bank per row; the read side walks complete rows
// without a ready signal. Taps are shared by the two lanes:
//   taps[0..3]  = top    x-1,x,x+1,x+2
//   taps[4..7]  = middle x-1,x,x+1,x+2
//   taps[8..11] = bottom x-1,x,x+1,x+2
// where x is the even pixel of the output pair.
module dpc_dynamic_window #(
    parameter integer WIDTH = 1280,
    parameter integer HEIGHT = 1024
)(
    input  wire         clk,
    input  wire         resetn,
    input  wire [19:0]  s_data,
    input  wire         s_valid,
    input  wire         s_sof,
    input  wire         s_eol,
    input  wire         s_packet_error,
    input  wire         s_global_fault,
    input  wire         flush,
    output wire [19:0]  m_center,
    output wire [119:0] m_taps,
    output wire         m_valid,
    output wire         m_sof,
    output wire         m_eol,
    output wire         m_eof,
    output wire         m_row_interior,
    output wire [1:0]   m_lane_interior,
    output wire         rd_frame_start,
    output reg          fault
);
    localparam integer PAIRS   = WIDTH / 2;
    localparam integer PAIR_AW = (PAIRS > 2) ? $clog2(PAIRS) : 1;
    localparam integer XW      = $clog2(WIDTH + 1);
    localparam integer YW      = $clog2(HEIGHT + 1);

    (* ram_style = "block" *) reg [19:0] line0 [0:PAIRS-1];
    (* ram_style = "block" *) reg [19:0] line1 [0:PAIRS-1];
    (* ram_style = "block" *) reg [19:0] line2 [0:PAIRS-1];
    (* ram_style = "block" *) reg [19:0] line3 [0:PAIRS-1];

    // ------------------------------------------------------------------
    // Write side: per-row ownership, frame and row tags.
    // ------------------------------------------------------------------
    reg [XW-1:0]       in_x;
    reg [YW-1:0]       in_y;
    reg                in_open;
    reg                wait_clean;
    reg [7:0]          wr_frame;
    reg [31:0]         wr_global_row;
    reg [3:0]          bank_valid;
    reg [7:0]          bank_frame [0:3];
    reg [YW-1:0]       bank_row   [0:3];

    wire               stream_fault = s_packet_error || s_global_fault;
    wire               clean_sof = s_valid && s_sof && !s_eol && !stream_fault &&
                                   (wait_clean || !in_open);
    wire               active_input = s_valid && !stream_fault && in_open && !wait_clean;
    wire               geom_fault = active_input &&
                                    (s_sof || (s_eol != (in_x == WIDTH-2)));
    wire               stray_valid = s_valid && !stream_fault && !wait_clean &&
                                     !in_open && !s_sof;
    wire               local_flush = flush || geom_fault || stray_valid;
    wire               push = clean_sof || (active_input && !geom_fault);

    wire [XW-1:0]      wr_x = clean_sof ? {XW{1'b0}} : in_x;
    wire [YW-1:0]      wr_y = clean_sof ? {YW{1'b0}} : in_y;
    wire [PAIR_AW-1:0] wr_addr = PAIR_AW'(wr_x >> 1);
    wire [1:0]         wr_bank = wr_global_row[1:0];

    always @(posedge clk) begin
        if (!resetn) begin
            in_x <= 0;
            in_y <= 0;
            in_open <= 0;
            wait_clean <= 1;
            wr_frame <= 0;
            wr_global_row <= 0;
            bank_valid <= 4'd0;
        end else begin
            if (local_flush) begin
                in_x <= 0;
                in_y <= 0;
                in_open <= 0;
                wait_clean <= 1;
                bank_valid <= 4'd0;
            end else if (push) begin
                if (clean_sof) begin
                    in_x <= XW'(2);
                    in_y <= 0;
                    in_open <= 1'b1;
                    wait_clean <= 1'b0;
                    wr_frame <= wr_frame + 1'b1;
                end else begin
                    in_x <= s_eol ? {XW{1'b0}} : in_x + XW'(2);
                    in_y <= s_eol ? in_y + 1'b1 : in_y;
                    in_open <= !(s_eol && (in_y == HEIGHT-1));
                end
                if (s_eol) begin
                    wr_global_row <= wr_global_row + 1'b1;
                end
                // First pair of a row takes ownership of the bank; the old row
                // tag dies before any new data is visible.
                if (wr_x == 0) begin
                    bank_valid[wr_bank] <= 1'b0;
                end
                if (s_eol) begin
                    bank_valid[wr_bank] <= 1'b1;
                    bank_frame[wr_bank] <= wr_frame;
                    bank_row[wr_bank] <= wr_y;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (push && wr_bank == 2'd0) line0[wr_addr] <= s_data;
        if (push && wr_bank == 2'd1) line1[wr_addr] <= s_data;
        if (push && wr_bank == 2'd2) line2[wr_addr] <= s_data;
        if (push && wr_bank == 2'd3) line3[wr_addr] <= s_data;
    end

    // ------------------------------------------------------------------
    // Read side: search the four tags, issue one pair per row bank per cycle.
    // rd_pair is the pair issued in the current cycle. The row ends when the
    // last pair is issued; the next row starts on the following cycle without
    // an idle beat whenever its tags are already complete.
    // ------------------------------------------------------------------
    // Tag registers are explicit inputs. A function that reads module globals
    // is not re-evaluated when only those globals change, leaving the
    // continuous sr_* result stale in XSim.
    function automatic [2:0] find_bank(input [7:0] f, input [YW-1:0] r, input [3:0] valid,
                                       input [7:0] frames [0:3], input [YW-1:0] rows [0:3]);
        integer i;
        begin
            find_bank = 3'b000;
            for (i = 0; i < 4; i = i + 1) begin
                if (valid[i] && (frames[i] == f) && (rows[i] == r)) begin
                    find_bank = {1'b1, i[1:0]};
                end
            end
        end
    endfunction

    reg                      rd_active;
    reg [YW-1:0]             rd_row;
    reg [7:0]                rd_frame;
    reg [PAIR_AW-1:0]        rd_pair;
    reg [1:0]                rd_top_bank;
    reg [1:0]                rd_mid_bank;
    reg [1:0]                rd_bot_bank;

    wire                     last_pair = rd_active && (rd_pair == PAIRS-1);
    wire [YW-1:0]            next_row = (rd_row == HEIGHT-1) ? {YW{1'b0}} : rd_row + 1'b1;
    wire                     next_wrap = last_pair && (rd_row == HEIGHT-1);
    wire [7:0]               next_frame = rd_frame + (next_wrap ? 1'b1 : 1'b0);
    wire [YW-1:0]            cand_row = last_pair ? next_row : rd_row;
    wire [7:0]               cand_frame = last_pair ? next_frame : rd_frame;
    wire [2:0]               sr_mid = find_bank(cand_frame, cand_row, bank_valid, bank_frame, bank_row);
    wire [2:0]               sr_top = find_bank(cand_frame, cand_row - 1'b1, bank_valid, bank_frame, bank_row);
    wire [2:0]               sr_bot = find_bank(cand_frame, cand_row + 1'b1, bank_valid, bank_frame, bank_row);
    wire                     cand_interior = (cand_row != 0) && (cand_row != HEIGHT-1);
    wire                     cand_ready = sr_mid[2] &&
                                          (!cand_interior || (sr_top[2] && sr_bot[2]));

    wire                     blocked = local_flush || stream_fault;
    wire                     issue = !blocked && (rd_active || cand_ready);
    wire [YW-1:0]            issue_row = rd_active ? rd_row : cand_row;
    wire [PAIR_AW-1:0]       issue_pair = rd_active ? rd_pair : {PAIR_AW{1'b0}};
    wire [1:0]               issue_mid_bank = rd_active ? rd_mid_bank : sr_mid[1:0];
    wire [1:0]               issue_top_bank = rd_active ? rd_top_bank : sr_top[1:0];
    wire [1:0]               issue_bot_bank = rd_active ? rd_bot_bank : sr_bot[1:0];
    wire                     issue_interior = (issue_row != 0) && (issue_row != HEIGHT-1);
    wire                     use_top = issue && issue_interior;
    wire                     use_mid = issue;
    wire                     use_bot = issue && issue_interior;

    wire                     re0 = (use_top && issue_top_bank == 2'd0) ||
                                   (use_mid && issue_mid_bank == 2'd0) ||
                                   (use_bot && issue_bot_bank == 2'd0);
    wire                     re1 = (use_top && issue_top_bank == 2'd1) ||
                                   (use_mid && issue_mid_bank == 2'd1) ||
                                   (use_bot && issue_bot_bank == 2'd1);
    wire                     re2 = (use_top && issue_top_bank == 2'd2) ||
                                   (use_mid && issue_mid_bank == 2'd2) ||
                                   (use_bot && issue_bot_bank == 2'd2);
    wire                     re3 = (use_top && issue_top_bank == 2'd3) ||
                                   (use_mid && issue_mid_bank == 2'd3) ||
                                   (use_bot && issue_bot_bank == 2'd3);

    reg [19:0] q0, q1, q2, q3;
    reg [1:0]  pb_top, pb_mid, pb_bot;
    always @(posedge clk) begin
        if (re0) q0 <= line0[issue_pair];
        if (re1) q1 <= line1[issue_pair];
        if (re2) q2 <= line2[issue_pair];
        if (re3) q3 <= line3[issue_pair];
        if (issue) begin
            pb_top <= issue_top_bank;
            pb_mid <= issue_mid_bank;
            pb_bot <= issue_bot_bank;
        end
    end

    wire [19:0] q_sel_top = (pb_top == 2'd0) ? q0 :
                            (pb_top == 2'd1) ? q1 :
                            (pb_top == 2'd2) ? q2 : q3;
    wire [19:0] q_sel_mid = (pb_mid == 2'd0) ? q0 :
                            (pb_mid == 2'd1) ? q1 :
                            (pb_mid == 2'd2) ? q2 : q3;
    wire [19:0] q_sel_bot = (pb_bot == 2'd0) ? q0 :
                            (pb_bot == 2'd1) ? q1 :
                            (pb_bot == 2'd2) ? q2 : q3;

    reg [19:0] s1_top, s2_top, s1_mid, s2_mid, s1_bot, s2_bot;
    always @(posedge clk) begin
        s2_top <= s1_top;
        s1_top <= q_sel_top;
        s2_mid <= s1_mid;
        s1_mid <= q_sel_mid;
        s2_bot <= s1_bot;
        s1_bot <= q_sel_bot;
    end

    // ------------------------------------------------------------------
    // Metadata: two stages behind the read request, aligned with s1.
    // ------------------------------------------------------------------
    reg        m1_valid, m2_valid;
    reg        m1_sof, m1_eol, m1_eof, m1_row_int, m1_first, m1_last;
    reg [1:0]  m1_lane_int;
    reg        m2_sof, m2_eol, m2_eof, m2_row_int, m2_first, m2_last;
    reg [1:0]  m2_lane_int;

    wire issue_sof = issue && (issue_row == 0) && (issue_pair == 0);
    wire issue_eol = issue && (issue_pair == PAIRS-1);
    wire issue_eof = issue_eol && (issue_row == HEIGHT-1);
    wire issue_row_int = issue_interior;
    wire issue_first = issue && (issue_pair == 0);
    wire issue_last = issue && (issue_pair == PAIRS-1);
    wire [1:0] issue_lane_int = {(issue_pair != PAIRS-1), (issue_pair != 0)};

    always @(posedge clk) begin
        if (!resetn || local_flush) begin
            m1_valid <= 1'b0;
            m2_valid <= 1'b0;
            m2_sof <= 1'b0;
            m2_eol <= 1'b0;
            m2_eof <= 1'b0;
        end else begin
            m1_valid <= issue;
            m2_valid <= m1_valid;
            if (issue) begin
                m1_sof <= issue_sof;
                m1_eol <= issue_eol;
                m1_eof <= issue_eof;
                m1_row_int <= issue_row_int;
                m1_first <= issue_first;
                m1_last <= issue_last;
                m1_lane_int <= issue_lane_int;
            end
            if (m1_valid) begin
                m2_sof <= m1_sof;
                m2_eol <= m1_eol;
                m2_eof <= m1_eof;
                m2_row_int <= m1_row_int;
                m2_first <= m1_first;
                m2_last <= m1_last;
                m2_lane_int <= m1_lane_int;
            end
        end
    end

    // Bank conflict: the write side must own the fourth bank while three read
    // banks are active. Any overlap means a tag was reused too early.
    wire bank_conflict = push && issue &&
                         ((wr_bank == issue_mid_bank) ||
                          (issue_interior && (wr_bank == issue_top_bank)) ||
                          (issue_interior && (wr_bank == issue_bot_bank)));
    always @(posedge clk) begin
        if (!resetn) fault <= 1'b0;
        else if (bank_conflict || geom_fault || stray_valid) fault <= 1'b1;
        else fault <= 1'b0;
    end

    // ------------------------------------------------------------------
    // Output taps at the registered window beat.
    // ------------------------------------------------------------------
    wire [9:0] t0 = (m2_row_int && !m2_first) ? s2_top[19:10] : 10'd0;
    wire [9:0] t1 = m2_row_int ? s1_top[9:0]  : 10'd0;
    wire [9:0] t2 = m2_row_int ? s1_top[19:10] : 10'd0;
    wire [9:0] t3 = (m2_row_int && !m2_last) ? q_sel_top[9:0] : 10'd0;
    wire [9:0] c0 = (m2_row_int && !m2_first) ? s2_mid[19:10] : 10'd0;
    wire [9:0] c1 = m2_row_int ? s1_mid[9:0]  : 10'd0;
    wire [9:0] c2 = m2_row_int ? s1_mid[19:10] : 10'd0;
    wire [9:0] c3 = (m2_row_int && !m2_last) ? q_sel_mid[9:0] : 10'd0;
    wire [9:0] b0 = (m2_row_int && !m2_first) ? s2_bot[19:10] : 10'd0;
    wire [9:0] b1 = m2_row_int ? s1_bot[9:0]  : 10'd0;
    wire [9:0] b2 = m2_row_int ? s1_bot[19:10] : 10'd0;
    wire [9:0] b3 = (m2_row_int && !m2_last) ? q_sel_bot[9:0] : 10'd0;

    assign m_taps = {b3, b2, b1, b0, c3, c2, c1, c0, t3, t2, t1, t0};
    assign m_center = s1_mid;
    assign m_valid = m2_valid;
    assign m_sof = m2_valid && m2_sof;
    assign m_eol = m2_valid && m2_eol;
    assign m_eof = m2_valid && m2_eof;
    assign m_row_interior = m2_row_int;
    assign m_lane_interior = m2_lane_int;
    assign rd_frame_start = issue_sof;

    always @(posedge clk) begin
        if (!resetn || local_flush) begin
            rd_active <= 1'b0;
            rd_row <= 0;
            rd_pair <= 0;
            rd_frame <= (local_flush && resetn) ? (wr_frame + 1'b1) : 8'd1;
            rd_top_bank <= 0;
            rd_mid_bank <= 0;
            rd_bot_bank <= 0;
        end else if (rd_active) begin
            // A blocked cycle (standalone stream fault) must not consume a
            // pair; the reader resumes at the same pair when the fault clears.
            if (issue) begin
                if (last_pair) begin
                    rd_active <= cand_ready;
                    rd_row <= next_row;
                    rd_frame <= next_frame;
                    rd_pair <= 0;
                    rd_top_bank <= sr_top[1:0];
                    rd_mid_bank <= sr_mid[1:0];
                    rd_bot_bank <= sr_bot[1:0];
                end else begin
                    rd_pair <= rd_pair + 1'b1;
                end
            end
        end else if (issue) begin
            // pair 0 is issued in this cycle; the state advances to pair 1.
            rd_active <= 1'b1;
            rd_pair <= 1'b1;
            rd_top_bank <= sr_top[1:0];
            rd_mid_bank <= sr_mid[1:0];
            rd_bot_bank <= sr_bot[1:0];
        end
    end
endmodule
