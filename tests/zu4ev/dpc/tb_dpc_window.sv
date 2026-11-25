`timescale 1ns/1ps
// Focused window regression: last pair of every row, bank selection at a row
// boundary, frame tags on back-to-back frames and drain with no further input.
module tb_dpc_window;
    parameter integer W = 8;
    parameter integer H = 4;
    localparam integer PAIRS = W/2;
    localparam integer FRAME_PAIRS = W*H/2;

    reg clk = 0;
    always #5 clk = ~clk;
    reg resetn = 0;
    reg sv = 0, ss = 0, se = 0;
    reg [19:0] sd = 0;

    wire [19:0]  mc;
    wire [119:0] mt;
    wire mv, ms, me, mfe, mri, rds, fault;
    wire [1:0] mli;

    dpc_dynamic_window #(.WIDTH(W),.HEIGHT(H)) dut (
        .clk(clk),.resetn(resetn),
        .s_data(sd),.s_valid(sv),.s_sof(ss),.s_eol(se),
        .s_packet_error(1'b0),.s_global_fault(1'b0),.flush(1'b0),
        .m_center(mc),.m_taps(mt),.m_valid(mv),.m_sof(ms),.m_eol(me),.m_eof(mfe),
        .m_row_interior(mri),.m_lane_interior(mli),
        .rd_frame_start(rds),.fault(fault));

    reg [19:0] bases [0:7];
    integer bases_n = 0;
    integer out_pairs = 0, out_eols = 0, out_sofs = 0, out_frames = 0;
    integer starts = 0, errors = 0;
    integer i;

    // rd_frame_start is a single-cycle pulse that starts when the input side
    // releases the row, so count it at the posedge that consumes it.
    always @(posedge clk) if (resetn && rds) starts = starts + 1;

    always @(negedge clk) begin
        if (resetn) begin
            if (fault) errors = errors + 1;
            if (mv) begin
                if (mc !== (bases[out_frames] + (out_pairs % (W*H/2)))) begin
                    $display("DATA pair %0d frame %0d got %h want %h",
                             out_pairs, out_frames, mc,
                             bases[out_frames] + (out_pairs % (W*H/2)));
                    errors = errors + 1;
                end
                if (ms !== (out_pairs % (W*H/2) == 0)) begin
                    $display("SOF position %0d", out_pairs); errors = errors + 1;
                end
                if (me !== (out_pairs % PAIRS == PAIRS-1)) begin
                    $display("EOL position %0d", out_pairs); errors = errors + 1;
                end
                if (mfe !== (out_pairs % (W*H/2) == W*H/2-1)) begin
                    $display("EOF position %0d", out_pairs); errors = errors + 1;
                end
                if (mri !== ((out_pairs % (W*H/2)) / PAIRS != 0 &&
                             (out_pairs % (W*H/2)) / PAIRS != H-1)) begin
                    $display("row interior %0d", out_pairs); errors = errors + 1;
                end
                if (mli !== {(out_pairs % PAIRS != PAIRS-1),
                             (out_pairs % PAIRS != 0)}) begin
                    $display("lane interior %0d", out_pairs); errors = errors + 1;
                end
                if (ms) out_sofs = out_sofs + 1;
                if (me) out_eols = out_eols + 1;
                out_pairs = out_pairs + 1;
                if (me && (out_pairs % (W*H/2) == 0)) out_frames = out_frames + 1;
            end
        end
    end

    task automatic send_frame(input [19:0] base);
        integer p;
        begin
            bases[bases_n] = base;
            bases_n = bases_n + 1;
            for (p = 0; p < FRAME_PAIRS; p = p + 1) begin
                @(negedge clk);
                sv = 1;
                ss = (p == 0);
                se = (p % PAIRS == PAIRS-1);
                sd = base + p;
            end
        end
    endtask

    task automatic idle_n(input integer cycles);
        integer p;
        begin
            for (p = 0; p < cycles; p = p + 1) begin
                @(negedge clk); sv = 0; ss = 0; se = 0; sd = 0;
            end
        end
    endtask

    initial begin
        repeat(3) @(negedge clk);
        resetn = 1;
        idle_n(2);
        // Original reproducer: one frame, then enough idle time to drain.
        send_frame(20'h00000);
        idle_n(40);
        if (out_pairs != FRAME_PAIRS || out_eols != H || out_sofs != 1 || out_frames != 1)
            $fatal(1,"single frame pairs=%0d eols=%0d sofs=%0d frames=%0d",
                   out_pairs,out_eols,out_sofs,out_frames);
        // Two adjacent frames exercise frame tags, bank reuse and the row
        // boundary without any idle beat between them.
        send_frame(20'h10000);
        send_frame(20'h20000);
        idle_n(40);
        if (out_pairs != 3*FRAME_PAIRS || out_eols != 3*H || out_sofs != 3 || out_frames != 3)
            $fatal(1,"three frames pairs=%0d eols=%0d sofs=%0d frames=%0d",
                   out_pairs,out_eols,out_sofs,out_frames);
        if (starts != 3) $fatal(1,"frame start pulses %0d",starts);
        if (errors != 0) $fatal(1,"window errors %0d",errors);
        $display("DPC_WINDOW_PASS %0dx%0d rows=%0d pairs=%0d eols=%0d frames=%0d contiguous+gap",
                 W,H,H,out_pairs,out_eols,out_frames);
        $finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
