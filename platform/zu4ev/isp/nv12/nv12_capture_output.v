`timescale 1ns/1ps
// Platform output boundary: final YUY2 tap, managed buffers, completed-frame IRQ.
module nv12_capture_output #(
    parameter integer WIDTH=1280, HEIGHT=1024, FIFO_DEPTH=256
) (
    input wire clk, resetn,
    input wire enable, stop_request,
    output wire idle,
    input wire [31:0] s_data,
    input wire s_valid, s_sof, s_eol, s_fault,
    input wire cfg_valid,
    output wire cfg_ready,
    input wire [1:0] cfg_slot,
    input wire [31:0] cfg_base, cfg_stride,
    output wire cfg_error, release_error,
    output wire frame_valid,
    input wire frame_ready,
    output wire [31:0] frame_base, frame_stride, frame_tag,
    input wire release_valid,
    input wire [31:0] release_tag,
    input wire irq_enable,
    output wire irq,
    output wire [31:0] dropped_frames, failed_frames,
    output wire [31:0] m_axi_awaddr,
    output wire [7:0] m_axi_awlen,
    output wire [2:0] m_axi_awsize,
    output wire [1:0] m_axi_awburst,
    output wire m_axi_awvalid,
    input wire m_axi_awready,
    output wire [127:0] m_axi_wdata,
    output wire [15:0] m_axi_wstrb,
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input wire m_axi_wready,
    input wire [1:0] m_axi_bresp,
    input wire m_axi_bvalid,
    output wire m_axi_bready
);
    wire desc_valid, desc_ready, result_valid, result_ready, result_error;
    wire [31:0] desc_base, desc_stride, desc_tag, result_tag;
    assign irq = irq_enable && frame_valid;
    nv12_buffer_pool #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) pool (
        .clk(clk),.resetn(resetn),.cfg_valid(cfg_valid),.cfg_ready(cfg_ready),
        .cfg_slot(cfg_slot),.cfg_base(cfg_base),.cfg_stride(cfg_stride),
        .cfg_error(cfg_error),.release_error(release_error),
        .desc_valid(desc_valid),.desc_ready(desc_ready),.desc_base(desc_base),
        .desc_stride(desc_stride),.desc_tag(desc_tag),.result_valid(result_valid),
        .result_error(result_error),.result_tag(result_tag),.result_ready(result_ready),
        .frame_valid(frame_valid),.frame_ready(frame_ready),.frame_base(frame_base),
        .frame_stride(frame_stride),.frame_tag(frame_tag),
        .release_valid(release_valid),.release_tag(release_tag),.failed_frames(failed_frames)
    );
    nv12_isp_ddr_sink #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.FIFO_DEPTH(FIFO_DEPTH)) sink (
        .clk(clk),.resetn(resetn),.enable(enable),.stop_request(stop_request),.idle(idle),.s_data(s_data),.s_valid(s_valid),.s_sof(s_sof),
        .s_eol(s_eol),.s_fault(s_fault),.desc_valid(desc_valid),.desc_ready(desc_ready),
        .desc_base(desc_base),.desc_stride(desc_stride),.desc_tag(desc_tag),
        .result_valid(result_valid),.result_ready(result_ready),.result_error(result_error),
        .result_tag(result_tag),.dropped_frames(dropped_frames),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready)
    );
endmodule
