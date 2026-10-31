`timescale 1ns/1ps
// RAW capture micro-architecture: video_clk owns registers, gate and guard.
// IDLE -> ARMED -> CAPTURE -> DRAIN -> RESULT is owned by the reused tap.
// One ARM epoch authorizes one frame; matching ACK releases the result.
// No CSI backpressure: FIFO overflow invalidates the complete frame.
// Guard observes only this VDMA master, including AW/WLAST/B retirement.
// Software programs 2560-byte stride/HSIZE, 1024 VSIZE and frame count=1.
// The following source SOF supplies the existing gate's closing lookahead;
// it is not an authorized second DDR frame. DMA buffers remain owned by the
// driver until this VDMA is stopped/reset, including on error or cancellation.
// Check VDMA DMASR as well as gate flags before publishing any buffer: passive
// guard catches bus/strobe/byte-count errors; VDMA internal status is software's
// responsibility. Shared system reset resets all channels; recovery uses only
// the dedicated VDMA software reset and matching gate ACK, never preview reset.
module raw10_capture #(parameter LINE_WORDS=640, FRAME_LINES=1024, FIFO_DEPTH=4096) (
    input wire  clk,
    input wire  resetn,
    output wire [31:0] m0_data,
    output wire  m0_valid,
    output wire  m0_sof,
    output wire  m0_eol,
    input wire  m0_ready,
    input wire  d0_awvalid,
    input wire  d0_awready,
    input wire  d0_wvalid,
    input wire  d0_wready,
    input wire  d0_wlast,
    input wire  d0_bvalid,
    input wire  d0_bready,
    input wire [15:0] d0_wstrb,
    input wire [1:0] d0_bresp,
    output wire  irq0,
    input wire [7:0] c0_s_axi_awaddr,
    input wire  c0_s_axi_awvalid,
    output wire  c0_s_axi_awready,
    input wire [31:0] c0_s_axi_wdata,
    input wire [3:0] c0_s_axi_wstrb,
    input wire  c0_s_axi_wvalid,
    output wire  c0_s_axi_wready,
    output wire [1:0] c0_s_axi_bresp,
    output wire  c0_s_axi_bvalid,
    input wire  c0_s_axi_bready,
    input wire [7:0] c0_s_axi_araddr,
    input wire  c0_s_axi_arvalid,
    output wire  c0_s_axi_arready,
    output wire [31:0] c0_s_axi_rdata,
    output wire [1:0] c0_s_axi_rresp,
    output wire  c0_s_axi_rvalid,
    input wire  c0_s_axi_rready,
    input wire [19:0] raw_data,
    input wire raw_valid,raw_sof,raw_eol,packet_error,global_fault
);
    wire [31:0] source_seq;
    wire [63:0] source_tick;
    // Independent RAW source clock; preview sequencing is untouched.
    capture_source_clock_v2 source_clock (
        .clk         (clk),
        .resetn      (resetn),
        .valid       (raw_valid),
        .sof         (raw_sof),
        .source_seq  (source_seq),
        .source_tick (source_tick)
    );

    // ---------------------------------------------------------------------
    // Dedicated RAW channel: accept the next observed SOF after ARM
    // Signals shared by this channel's guard, frame gate and AXI registers.
    // ---------------------------------------------------------------------
    // Commands and epoch handshakes
    wire        c0_arm;
    wire        c0_abort_capture;
    wire        c0_ack;
    wire        c0_clear_stats;
    wire [31:0] c0_arm_epoch;
    wire [31:0] c0_ack_epoch;

    // Capture result and counters
    wire [31:0] c0_status;
    wire        c0_result_valid;
    wire [31:0] c0_result_epoch;
    wire [31:0] c0_result_flags;
    wire [31:0] c0_input_seq;
    wire [31:0] c0_result_seq;
    wire [31:0] c0_result_words;
    wire [31:0] c0_result_lines;
    wire [31:0] c0_dropped;
    wire [31:0] c0_overflows;
    wire [31:0] c0_complete;

    // Source timing and arm diagnostics
    wire [31:0] c0_deadline_miss;
    wire [31:0] c0_arm_accept_epoch;
    wire [31:0] c0_arm_target_seq;
    wire [63:0] c0_arm_tick;
    wire [63:0] c0_result_sof_tick;
    wire [63:0] c0_result_done_tick;

    // Memory write completion
    wire        c0_epoch_start;
    wire        c0_dma_done;
    wire        c0_dma_error;
    wire        c0_quiescent;
    wire [31:0] c0_guard_bytes;

    // Observe VDMA writes at the DDR-facing AXI boundary
    vdma_write_guard_v2 #(
        .EXPECTED_BYTES (LINE_WORDS*FRAME_LINES*4)
    ) guard0 (
        .clk       (clk),
        .resetn    (resetn),
        .start     (c0_epoch_start),
        .awvalid   (d0_awvalid),
        .awready   (d0_awready),
        .wvalid    (d0_wvalid),
        .wready    (d0_wready),
        .wlast     (d0_wlast),
        .wstrb     (d0_wstrb),
        .bvalid    (d0_bvalid),
        .bready    (d0_bready),
        .bresp     (d0_bresp),
        .retired   (c0_dma_done),
        .error     (c0_dma_error),
        .quiescent (c0_quiescent),
        .bytes     (c0_guard_bytes)
    );

    // Arm only from IDLE. Software must stop/reset this dedicated VDMA
    // before ACK after failure; no preview reset is needed or permitted.
    assign c0_epoch_start = c0_arm && c0_status[0] && !c0_abort_capture;
    assign c0_deadline_miss = 0;
    assign c0_arm_accept_epoch = c0_result_epoch;
    assign c0_arm_target_seq = 0;
    reg [63:0] arm_tick,sof_tick,done_tick;
    reg result_seen;
    always @(posedge clk) begin
        if (!resetn) begin
            arm_tick<=0;sof_tick<=0;done_tick<=0;result_seen<=0;
        end else begin
            result_seen<=c0_result_valid;
            if(c0_epoch_start) arm_tick<=source_tick;
            if(c0_status[1] && raw_valid && raw_sof) sof_tick<=source_tick;
            if(c0_result_valid && !result_seen) done_tick<=source_tick;
        end
    end
    assign c0_arm_tick=arm_tick;
    assign c0_result_sof_tick=sof_tick;
    assign c0_result_done_tick=done_tick;
    raw10_capture_tap #(.LINE_WORDS(LINE_WORDS),.FRAME_LINES(FRAME_LINES),.FIFO_DEPTH(FIFO_DEPTH)) tap (
        .clk(clk),.resetn(resetn),.arm(c0_arm),.abort_capture(c0_abort_capture),
        .ack(c0_ack),.clear_stats(c0_clear_stats),.arm_epoch(c0_arm_epoch),.ack_epoch(c0_ack_epoch),
        .s_data(raw_data),.s_valid(raw_valid),.s_sof(raw_sof),.s_eol(raw_eol),
        .s_packet_error(packet_error),.s_global_fault(global_fault),
        .dma_done(c0_dma_done),.dma_error(c0_dma_error),
        .m_data(m0_data),.m_valid(m0_valid),.m_sof(m0_sof),.m_eol(m0_eol),.m_ready(m0_ready),
        .status(c0_status),.result_valid(c0_result_valid),.result_epoch(c0_result_epoch),
        .result_flags(c0_result_flags),.input_seq(c0_input_seq),.result_seq(c0_result_seq),
        .result_words(c0_result_words),.result_lines(c0_result_lines),.dropped(c0_dropped),
        .overflows(c0_overflows),.complete(c0_complete)
    );

    // Expose commands, results and diagnostics to PS
    raw10_capture_regs #(
        .CHANNEL_ID (2),
        .PHASE      (0)
    ) regs0 (
        .clk              (clk),
        .resetn           (resetn),
        .s_axi_awaddr     (c0_s_axi_awaddr),
        .s_axi_awvalid    (c0_s_axi_awvalid),
        .s_axi_awready    (c0_s_axi_awready),
        .s_axi_wdata      (c0_s_axi_wdata),
        .s_axi_wstrb      (c0_s_axi_wstrb),
        .s_axi_wvalid     (c0_s_axi_wvalid),
        .s_axi_wready     (c0_s_axi_wready),
        .s_axi_bresp      (c0_s_axi_bresp),
        .s_axi_bvalid     (c0_s_axi_bvalid),
        .s_axi_bready     (c0_s_axi_bready),
        .s_axi_araddr     (c0_s_axi_araddr),
        .s_axi_arvalid    (c0_s_axi_arvalid),
        .s_axi_arready    (c0_s_axi_arready),
        .s_axi_rdata      (c0_s_axi_rdata),
        .s_axi_rresp      (c0_s_axi_rresp),
        .s_axi_rvalid     (c0_s_axi_rvalid),
        .s_axi_rready     (c0_s_axi_rready),
        .arm              (c0_arm),
        .abort_capture    (c0_abort_capture),
        .ack              (c0_ack),
        .clear_stats      (c0_clear_stats),
        .arm_epoch        (c0_arm_epoch),
        .ack_epoch        (c0_ack_epoch),
        .status           (c0_status),
        .result_epoch     (c0_result_epoch),
        .result_flags     (c0_result_flags),
        .input_seq        (c0_input_seq),
        .result_seq       (c0_result_seq),
        .result_words     (c0_result_words),
        .result_lines     (c0_result_lines),
        .dropped          (c0_dropped),
        .overflows        (c0_overflows),
        .complete         (c0_complete),
        .deadline_miss    (c0_deadline_miss),
        .arm_accept_epoch (c0_arm_accept_epoch),
        .arm_target_seq   (c0_arm_target_seq),
        .guard_bytes      (c0_guard_bytes),
        .arm_tick         (c0_arm_tick),
        .result_sof_tick  (c0_result_sof_tick),
        .result_done_tick (c0_result_done_tick),
        .result_valid     (c0_result_valid),
        .source_tick      (source_tick),
        .guard_status     ({29'b0,c0_quiescent,c0_dma_error,c0_dma_done}),
        .irq              (irq0)
    );

endmodule
