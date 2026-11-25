`timescale 1ns/1ps
// Final ISP tap; descriptor allocation is aligned to source SOF.
module nv12_isp_ddr_sink #(
    parameter integer WIDTH=1280, HEIGHT=1024, FIFO_DEPTH=256
) (
    input wire clk, resetn,
    input wire enable, stop_request,
    output wire idle,
    input wire [31:0] s_data,
    input wire s_valid, s_sof, s_eol, s_fault,
    input wire desc_valid,
    output wire desc_ready,
    input wire [31:0] desc_base, desc_stride, desc_tag,
    output wire result_valid, result_error,
    output wire [31:0] result_tag,
    input wire result_ready,
    output reg [31:0] dropped_frames,
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
    reg capturing;
    wire writer_ready, writer_quiescent, allocate;
    wire running = enable && !stop_request;
    wire [15:0] y_data, uv_data;
    wire y_valid, uv_valid, y_eof, uv_eof, y_ready, uv_ready;
    wire converter_abort, converter_done;
    wire source_sof = s_valid && s_sof;
    assign desc_ready = running && writer_ready && source_sof && !s_fault;
    assign idle = !enable && writer_quiescent && !capturing && !y_valid && !uv_valid;
    assign allocate = desc_valid && desc_ready;

    always @(posedge clk) begin
        if (!resetn) begin
            capturing<=0;
            dropped_frames<=0;
        end else begin
            if (converter_abort || converter_done || s_fault || !running) begin capturing<=0; end
            if (source_sof && running) begin
                capturing<=allocate;
                if (!allocate) begin dropped_frames<=dropped_frames+1'b1; end
            end
        end
    end
    isp_yuy2_nv12 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) converter (
        .clk(clk),.resetn(resetn),.s_data(s_data),
        .s_valid(running && s_valid && (source_sof ? allocate : capturing)),
        .s_sof(s_sof),.s_eol(s_eol),.s_fault(s_fault || !running),
        .y_data(y_data),.y_valid(y_valid),.y_sof(),.y_eol(),.y_eof(y_eof),.y_ready(y_ready),
        .uv_data(uv_data),.uv_valid(uv_valid),.uv_sof(),.uv_eol(),.uv_eof(uv_eof),.uv_ready(uv_ready),
        .frame_abort(converter_abort),.frame_done(converter_done)
    );
    nv12_ddr_writer #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.FIFO_DEPTH(FIFO_DEPTH)) writer (
        .clk(clk),.resetn(resetn),.desc_valid(allocate),.desc_ready(writer_ready),
        .desc_base(desc_base),.desc_stride(desc_stride),.desc_tag(desc_tag),
        .y_data(y_data),.uv_data(uv_data),.y_valid(y_valid),.uv_valid(uv_valid),
        .y_eof(y_eof),.uv_eof(uv_eof),.y_ready(y_ready),.uv_ready(uv_ready),
        .frame_abort(!running || converter_abort || (s_fault && capturing)),
        .quiescent(writer_quiescent),
        .result_valid(result_valid),.result_error(result_error),.result_tag(result_tag),
        .result_ready(result_ready),
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
