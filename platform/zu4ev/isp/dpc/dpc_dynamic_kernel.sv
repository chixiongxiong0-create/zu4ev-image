`timescale 1ns/1ps
// Two-lane DPC decision pipeline. Stage 1 registers the neighbour extremes and
// the four direction differences. Stage 2 performs the flat/hot/cold tests and
// selects the smoothest symmetric pair. Stage 3 rounds the pair mean and drives
// the output. Already repaired pixels are never fed back: every tap comes from
// the window's original input line banks.
module dpc_dynamic_kernel #(
    parameter integer WIDTH = 1280,
    parameter integer HEIGHT = 1024
)(
    input  wire         clk,
    input  wire         resetn,
    input  wire         flush,
    input  wire [19:0]  s_center,
    input  wire [119:0] s_taps,
    input  wire         s_valid,
    input  wire         s_sof,
    input  wire         s_eol,
    input  wire         s_eof,
    input  wire         s_row_interior,
    input  wire [1:0]   s_lane_interior,
    input  wire [1:0]   cfg_mode,
    input  wire         cfg_hot_en,
    input  wire         cfg_cold_en,
    input  wire [9:0]   cfg_hot_margin,
    input  wire [9:0]   cfg_cold_margin,
    input  wire [9:0]   cfg_flat_limit,
    output wire [19:0]  m_data,
    output wire         m_valid,
    output wire         m_sof,
    output wire         m_eol,
    output wire         m_eof,
    output reg  [31:0]  frame_seq,
    output reg  [31:0]  frame_hot,
    output reg  [31:0]  frame_cold,
    output reg  [31:0]  frame_repair
);
    function automatic [9:0] min2(input [9:0] a, input [9:0] b);
        min2 = (a < b) ? a : b;
    endfunction
    function automatic [9:0] max2(input [9:0] a, input [9:0] b);
        max2 = (a > b) ? a : b;
    endfunction
    function automatic [9:0] absdiff(input [9:0] a, input [9:0] b);
        absdiff = (a >= b) ? (a - b) : (b - a);
    endfunction

    // Shared 4x3 taps: top x-1..x+2, middle x-1..x+2, bottom x-1..x+2.
    wire [9:0] t0 = s_taps[9:0];
    wire [9:0] t1 = s_taps[19:10];
    wire [9:0] t2 = s_taps[29:20];
    wire [9:0] t3 = s_taps[39:30];
    wire [9:0] m0 = s_taps[49:40];
    wire [9:0] m1 = s_taps[59:50];
    wire [9:0] m2 = s_taps[69:60];
    wire [9:0] m3 = s_taps[79:70];
    wire [9:0] b0 = s_taps[89:80];
    wire [9:0] b1 = s_taps[99:90];
    wire [9:0] b2 = s_taps[109:100];
    wire [9:0] b3 = s_taps[119:110];

    // Lane 0 neighbours exclude the centre m1; lane 1 excludes m2.
    wire [9:0] lo0_c = min2(min2(min2(t0, t1), min2(t2, m0)),
                            min2(min2(m2, b0), min2(b1, b2)));
    wire [9:0] hi0_c = max2(max2(max2(t0, t1), max2(t2, m0)),
                            max2(max2(m2, b0), max2(b1, b2)));
    wire [9:0] lo1_c = min2(min2(min2(t1, t2), min2(t3, m1)),
                            min2(min2(m3, b1), min2(b2, b3)));
    wire [9:0] hi1_c = max2(max2(max2(t1, t2), max2(t3, m1)),
                            max2(max2(m3, b1), max2(b2, b3)));

    // ------------------------------------------------------------------
    // Stage 1
    // ------------------------------------------------------------------
    reg [9:0]   lo0_1, hi0_1, dh0_1, dv0_1, dd10_1, dd20_1;
    reg [9:0]   lo1_1, hi1_1, dh1_1, dv1_1, dd11_1, dd21_1;
    reg [119:0] taps_1;
    reg [19:0]  center_1;
    reg         valid_1, sof_1, eol_1, eof_1, rowint_1;
    reg [1:0]   laneint_1;
    reg [1:0]   mode_1;
    reg         hoten_1, colden_1;
    reg [9:0]   hm_1, cm_1, fl_1;

    reg [1:0]   f_mode;
    reg         f_hot_en, f_cold_en;
    reg [9:0]   f_hm, f_cm, f_fl;

    always @(posedge clk) begin
        if (!resetn || flush) begin
            valid_1 <= 1'b0;
            f_mode <= 2'd0;
            f_hot_en <= 1'b0;
            f_cold_en <= 1'b0;
            f_hm <= 10'd32;
            f_cm <= 10'd32;
            f_fl <= 10'd24;
        end else begin
            valid_1 <= s_valid;
            if (s_valid) begin
                mode_1 <= s_sof ? cfg_mode : f_mode;
                hoten_1 <= s_sof ? cfg_hot_en : f_hot_en;
                colden_1 <= s_sof ? cfg_cold_en : f_cold_en;
                hm_1 <= s_sof ? cfg_hot_margin : f_hm;
                cm_1 <= s_sof ? cfg_cold_margin : f_cm;
                fl_1 <= s_sof ? cfg_flat_limit : f_fl;
                lo0_1 <= lo0_c;
                hi0_1 <= hi0_c;
                lo1_1 <= lo1_c;
                hi1_1 <= hi1_c;
                dh0_1 <= absdiff(m0, m2);
                dv0_1 <= absdiff(t1, b1);
                dd10_1 <= absdiff(t0, b2);
                dd20_1 <= absdiff(t2, b0);
                dh1_1 <= absdiff(m1, m3);
                dv1_1 <= absdiff(t2, b2);
                dd11_1 <= absdiff(t1, b3);
                dd21_1 <= absdiff(t3, b1);
                taps_1 <= s_taps;
                center_1 <= s_center;
                sof_1 <= s_sof;
                eol_1 <= s_eol;
                eof_1 <= s_eof;
                rowint_1 <= s_row_interior;
                laneint_1 <= s_lane_interior;
            end
            if (s_valid && s_sof) begin
                f_mode <= cfg_mode;
                f_hot_en <= cfg_hot_en;
                f_cold_en <= cfg_cold_en;
                f_hm <= cfg_hot_margin;
                f_cm <= cfg_cold_margin;
                f_fl <= cfg_flat_limit;
            end
        end
    end

    // ------------------------------------------------------------------
    // Stage 2
    // ------------------------------------------------------------------
    wire flat0_c = ((hi0_1 - lo0_1) <= fl_1);
    wire flat1_c = ((hi1_1 - lo1_1) <= fl_1);
    wire hot0_c = flat0_c && hoten_1 &&
                  ({1'b0,center_1[9:0]} > ({1'b0,hi0_1} + {1'b0,hm_1}));
    wire hot1_c = flat1_c && hoten_1 &&
                  ({1'b0,center_1[19:10]} > ({1'b0,hi1_1} + {1'b0,hm_1}));
    wire cold0_c = flat0_c && colden_1 &&
                   (({1'b0,center_1[9:0]} + {1'b0,cm_1}) < {1'b0,lo0_1});
    wire cold1_c = flat1_c && colden_1 &&
                   (({1'b0,center_1[19:10]} + {1'b0,cm_1}) < {1'b0,lo1_1});

    reg [9:0] pa0, pb0, pa1, pb1;
    always @* begin
        // Tie order: horizontal, vertical, TL-BR, TR-BL.
        if ((dh0_1 <= dv0_1) && (dh0_1 <= dd10_1) && (dh0_1 <= dd20_1)) begin
            pa0 = taps_1[49:40];
            pb0 = taps_1[69:60];
        end else if ((dv0_1 <= dd10_1) && (dv0_1 <= dd20_1)) begin
            pa0 = taps_1[19:10];
            pb0 = taps_1[99:90];
        end else if (dd10_1 <= dd20_1) begin
            pa0 = taps_1[9:0];
            pb0 = taps_1[109:100];
        end else begin
            pa0 = taps_1[29:20];
            pb0 = taps_1[89:80];
        end
        if ((dh1_1 <= dv1_1) && (dh1_1 <= dd11_1) && (dh1_1 <= dd21_1)) begin
            pa1 = taps_1[59:50];
            pb1 = taps_1[79:70];
        end else if ((dv1_1 <= dd11_1) && (dv1_1 <= dd21_1)) begin
            pa1 = taps_1[29:20];
            pb1 = taps_1[109:100];
        end else if (dd11_1 <= dd21_1) begin
            pa1 = taps_1[19:10];
            pb1 = taps_1[119:110];
        end else begin
            pa1 = taps_1[39:30];
            pb1 = taps_1[99:90];
        end
    end

    reg         valid_2, sof_2, eol_2, eof_2, rowint_2;
    reg [1:0]   laneint_2, mode_2;
    reg         hot2_0, hot2_1, cold2_0, cold2_1;
    reg [19:0]  center_2;
    reg [9:0]   a0_2, b0_2, a1_2, b1_2;

    always @(posedge clk) begin
        if (!resetn || flush) begin
            valid_2 <= 1'b0;
        end else begin
            valid_2 <= valid_1;
            if (valid_1) begin
                sof_2 <= sof_1;
                eol_2 <= eol_1;
                eof_2 <= eof_1;
                rowint_2 <= rowint_1;
                laneint_2 <= laneint_1;
                mode_2 <= mode_1;
                hot2_0 <= hot0_c;
                hot2_1 <= hot1_c;
                cold2_0 <= cold0_c;
                cold2_1 <= cold1_c;
                center_2 <= center_1;
                a0_2 <= pa0;
                b0_2 <= pb0;
                a1_2 <= pa1;
                b1_2 <= pb1;
            end
        end
    end

    // ------------------------------------------------------------------
    // Stage 3
    // ------------------------------------------------------------------
    // The outermost pixel ring never becomes a candidate, not even a counted
    // one: both the repair and the observation counters are lane/row gated.
    wire        count0 = rowint_2 && laneint_2[0];
    wire        count1 = rowint_2 && laneint_2[1];
    wire        cand0 = count0 && (hot2_0 || cold2_0);
    wire        cand1 = count1 && (hot2_1 || cold2_1);
    wire [10:0] mean0 = ({1'b0,a0_2} + {1'b0,b0_2} + 11'd1) >> 1;
    wire [10:0] mean1 = ({1'b0,a1_2} + {1'b0,b1_2} + 11'd1) >> 1;
    wire [9:0]  val0 = ((mode_2 == 2'd2) && cand0) ? mean0[9:0] : center_2[9:0];
    wire [9:0]  val1 = ((mode_2 == 2'd2) && cand1) ? mean1[9:0] : center_2[19:10];

    // Stage 3 registers the repaired pixels, the output metadata and the frame
    // accumulator together. The sums use the stage-2 candidate flags and the
    // stage-2 SOF/EOF, so the counters describe the same beat that is being
    // registered into data_3. The output markers use the matching stage-3
    // registers, keeping m_data and m_valid/m_sof/m_eol/m_eof aligned.
    wire        count_en2 = (mode_2 != 2'd0);
    wire        repair_en2 = (mode_2 == 2'd2);
    wire [31:0] add_hot = ((count_en2 && count0 && hot2_0) ? 32'd1 : 32'd0) +
                          ((count_en2 && count1 && hot2_1) ? 32'd1 : 32'd0);
    wire [31:0] add_cold = ((count_en2 && count0 && cold2_0) ? 32'd1 : 32'd0) +
                           ((count_en2 && count1 && cold2_1) ? 32'd1 : 32'd0);
    wire [31:0] add_repair = ((repair_en2 && cand0) ? 32'd1 : 32'd0) +
                             ((repair_en2 && cand1) ? 32'd1 : 32'd0);

    reg [31:0] acc_hot, acc_cold, acc_repair;

    wire [31:0] sum_hot = (sof_2 ? 32'd0 : acc_hot) + add_hot;
    wire [31:0] sum_cold = (sof_2 ? 32'd0 : acc_cold) + add_cold;
    wire [31:0] sum_repair = (sof_2 ? 32'd0 : acc_repair) + add_repair;

    reg        valid_3, sof_3, eol_3, eof_3;
    reg [19:0] data_3;

    always @(posedge clk) begin
        if (!resetn) begin
            valid_3 <= 1'b0;
            sof_3 <= 1'b0;
            eol_3 <= 1'b0;
            eof_3 <= 1'b0;
            data_3 <= 20'd0;
            acc_hot <= 0;
            acc_cold <= 0;
            acc_repair <= 0;
            frame_seq <= 0;
            frame_hot <= 0;
            frame_cold <= 0;
            frame_repair <= 0;
        end else if (flush) begin
            valid_3 <= 1'b0;
            sof_3 <= 1'b0;
            eol_3 <= 1'b0;
            eof_3 <= 1'b0;
            acc_hot <= 0;
            acc_cold <= 0;
            acc_repair <= 0;
        end else begin
            valid_3 <= valid_2;
            if (valid_2) begin
                sof_3 <= sof_2;
                eol_3 <= eol_2;
                eof_3 <= eof_2;
                data_3 <= {val1, val0};
                acc_hot <= sum_hot;
                acc_cold <= sum_cold;
                acc_repair <= sum_repair;
                if (eof_2) begin
                    frame_hot <= sum_hot;
                    frame_cold <= sum_cold;
                    frame_repair <= sum_repair;
                    frame_seq <= frame_seq + 1'b1;
                end
            end
        end
    end

    assign m_data = data_3;
    assign m_valid = valid_3;
    assign m_sof = valid_3 && sof_3;
    assign m_eol = valid_3 && eol_3;
    assign m_eof = valid_3 && eof_3;
endmodule
