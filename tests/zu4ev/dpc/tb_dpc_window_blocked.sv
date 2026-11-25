`timescale 1ns/1ps
// Focused window regression: a stream fault in the cycle where row 0 first
// becomes readable must not consume pair 0. A reader that advances on
// cand_ready alone starts at pair 1 and corrupts the frame.
module tb_dpc_window_blocked;
    localparam integer W = 8;
    localparam integer H = 4;
    localparam integer PAIRS = W/2;

    reg clk = 0, resetn = 0, sv = 0, ss = 0, se = 0, sf = 0;
    reg [19:0] sd = 0;
    wire [19:0]  mc;
    wire [119:0] mt;
    wire mv, ms, me, mfe, mri, rds, fault;
    wire [1:0] mli;
    integer n = 0, eols = 0, i;
    always #5 clk = ~clk;

    dpc_dynamic_window #(.WIDTH(W),.HEIGHT(H)) dut (
        .clk(clk),.resetn(resetn),
        .s_data(sd),.s_valid(sv),.s_sof(ss),.s_eol(se),
        .s_packet_error(1'b0),.s_global_fault(sf),.flush(1'b0),
        .m_center(mc),.m_taps(mt),.m_valid(mv),.m_sof(ms),.m_eol(me),.m_eof(mfe),
        .m_row_interior(mri),.m_lane_interior(mli),
        .rd_frame_start(rds),.fault(fault));

    always @(negedge clk) begin
        if (resetn && mv) begin
            if (mc !== n[19:0]) $display("DATA_MISMATCH index=%0d got=%h", n, mc);
            n = n + 1;
            if (me) eols = eols + 1;
        end
        if (resetn && fault) $display("FAULT observed index=%0d", n);
    end

    initial begin
        repeat(3) @(negedge clk);
        resetn = 1;
        // Row 0: pairs 0..3.
        for (i = 0; i < PAIRS; i = i + 1) begin
            @(negedge clk);
            sv = 1; ss = (i == 0); se = (i == PAIRS-1); sd = i;
        end
        // Pair 4 is held while a one-cycle stream fault blocks the reader.
        @(negedge clk);
        sv = 1; ss = 0; se = 0; sd = 4; sf = 1;
        @(negedge clk);
        sf = 0; // Pair 4 is accepted on the next posedge.
        for (i = 5; i < PAIRS*H; i = i + 1) begin
            @(negedge clk);
            sv = 1; ss = 0; se = (i % PAIRS == PAIRS-1); sd = i;
        end
        @(negedge clk); sv = 0; ss = 0; se = 0; sd = 0;
        repeat(40) @(negedge clk);
        if (n != PAIRS*H || eols != H)
            $fatal(1,"got pairs=%0d eols=%0d, expected %0d/%0d", n, eols, PAIRS*H, H);
        $display("DPC_BLOCKED_START_PASS pairs=%0d eols=%0d", n, eols);
        $finish;
    end
    initial begin #1000000; $fatal(1,"timeout"); end
endmodule
