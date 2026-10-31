`timescale 1ns/1ps
module isp #(parameter BYPASS=0, PIPELINE=0, LINE_WORDS=640, FRAME_LINES=1024, USE_LTM=0, USE_TNR=0, ISP_RUNTIME=0) (output wire [511:0] ibex_stats_o, input wire ibex_cfg_reset_ni,

    input wire  clk,
    input wire  resetn,
    input wire [19:0] s_data,
    input wire  s_valid,
    input wire  s_sof,
    input wire  s_eol,
    output wire  s_ready,
    output wire [31:0] m_data,
    output wire  m_valid,
    output wire  m_sof,
    output wire  m_eol,
    input wire  m_ready,
    input wire [15:0] tnr_axi_awaddr,
    input wire  tnr_axi_awvalid,
    output wire  tnr_axi_awready,
    input wire [31:0] tnr_axi_wdata,
    input wire [3:0] tnr_axi_wstrb,
    input wire  tnr_axi_wvalid,
    output wire  tnr_axi_wready,
    output wire [1:0] tnr_axi_bresp,
    output wire  tnr_axi_bvalid,
    input wire  tnr_axi_bready,
    input wire [15:0] tnr_axi_araddr,
    input wire  tnr_axi_arvalid,
    output wire  tnr_axi_arready,
    output wire [31:0] tnr_axi_rdata,
    output wire [1:0] tnr_axi_rresp,
    output wire  tnr_axi_rvalid,
    input wire  tnr_axi_rready,
    input wire  tnr_calib_done,
    output wire [31:0] tnr_mem_awaddr,
    output wire [7:0] tnr_mem_awlen,
    output wire  tnr_mem_awvalid,
    input wire  tnr_mem_awready,
    output wire [127:0] tnr_mem_wdata,
    output wire [15:0] tnr_mem_wstrb,
    output wire  tnr_mem_wlast,
    output wire  tnr_mem_wvalid,
    input wire  tnr_mem_wready,
    input wire [1:0] tnr_mem_bresp,
    input wire  tnr_mem_bvalid,
    output wire  tnr_mem_bready,
    output wire [31:0] tnr_mem_araddr,
    output wire [7:0] tnr_mem_arlen,
    output wire  tnr_mem_arvalid,
    input wire  tnr_mem_arready,
    input wire [127:0] tnr_mem_rdata,
    input wire [1:0] tnr_mem_rresp,
    input wire  tnr_mem_rlast,
    input wire  tnr_mem_rvalid,
    output wire  tnr_mem_rready,
    input wire [15:0] isp_axi_awaddr,
    input wire  isp_axi_awvalid,
    output wire  isp_axi_awready,
    input wire [31:0] isp_axi_wdata,
    input wire [3:0] isp_axi_wstrb,
    input wire  isp_axi_wvalid,
    output wire  isp_axi_wready,
    output wire [1:0] isp_axi_bresp,
    output wire  isp_axi_bvalid,
    input wire  isp_axi_bready,
    input wire [15:0] isp_axi_araddr,
    input wire  isp_axi_arvalid,
    output wire  isp_axi_arready,
    output wire [31:0] isp_axi_rdata,
    output wire [1:0] isp_axi_rresp,
    output wire  isp_axi_rvalid,
    input wire  isp_axi_rready,
    input wire  packet_error,
    input wire  global_fault,
    output wire  m_packet_error,
    output wire  m_global_fault
);
    generate if (!PIPELINE) begin: LEGACY

    // Add future RAW-domain stages before this converter, and YUV-domain
    // stages after it. Propagate READY and delay SOF/EOL with their pixels.
    // Adding registers changes latency: update capture fault alignment too.
    raw10_to_yuy2 #(.BYPASS(BYPASS)) raw10_2_yuv_i (
        .clk(clk),
        .resetn(resetn),
        .s_data(s_data),
        .s_valid(s_valid),
        .s_sof(s_sof),
        .s_eol(s_eol),
        .s_ready(s_ready),
        .m_data(m_data),
        .m_valid(m_valid),
        .m_sof(m_sof),
        .m_eol(m_eol),
        .m_ready(m_ready)
    );
        assign tnr_axi_awready = 'b0;
        assign tnr_axi_wready = 'b0;
        assign tnr_axi_bresp = 'b0;
        assign tnr_axi_bvalid = 'b0;
        assign tnr_axi_arready = 'b0;
        assign tnr_axi_rdata = 'b0;
        assign tnr_axi_rresp = 'b0;
        assign tnr_axi_rvalid = 'b0;
        assign tnr_mem_awaddr = 'b0;
        assign tnr_mem_awlen = 'b0;
        assign tnr_mem_awvalid = 'b0;
        assign tnr_mem_wdata = 'b0;
        assign tnr_mem_wstrb = 'b0;
        assign tnr_mem_wlast = 'b0;
        assign tnr_mem_wvalid = 'b0;
        assign tnr_mem_bready = 'b0;
        assign tnr_mem_araddr = 'b0;
        assign tnr_mem_arlen = 'b0;
        assign tnr_mem_arvalid = 'b0;
        assign tnr_mem_rready = 'b0;
        assign isp_axi_awready = 'b0;
        assign isp_axi_wready = 'b0;
        assign isp_axi_bresp = 'b0;
        assign isp_axi_bvalid = 'b0;
        assign isp_axi_arready = 'b0;
        assign isp_axi_rdata = 'b0;
        assign isp_axi_rresp = 'b0;
        assign isp_axi_rvalid = 'b0;
        assign m_packet_error = 'b0;
        assign m_global_fault = 'b0;
    end else begin: PIPELINE_PATH
    assign s_ready = 1'b1;
    wire [31:0] pre_tnr_data;
    wire pre_tnr_valid,pre_tnr_sof,pre_tnr_eol,pre_tnr_packet,pre_tnr_fault;
    if(USE_TNR) begin: TEMPORAL
        isp_tnr_node #(.WIDTH(LINE_WORDS*2),.HEIGHT(FRAME_LINES)) temporal (
            .clk(clk),.resetn(resetn),.calib_done(tnr_calib_done),
            .s_data(pre_tnr_data),.s_valid(pre_tnr_valid),.s_sof(pre_tnr_sof),
            .s_eol(pre_tnr_eol),.s_fault(pre_tnr_packet || pre_tnr_fault),
            .m_data(m_data),.m_valid(m_valid),.m_sof(m_sof),.m_eol(m_eol),.m_fault(m_global_fault),
            .s_axi_awaddr(tnr_axi_awaddr),
            .s_axi_awvalid(tnr_axi_awvalid),
            .s_axi_awready(tnr_axi_awready),
            .s_axi_wdata(tnr_axi_wdata),
            .s_axi_wstrb(tnr_axi_wstrb),
            .s_axi_wvalid(tnr_axi_wvalid),
            .s_axi_wready(tnr_axi_wready),
            .s_axi_bresp(tnr_axi_bresp),
            .s_axi_bvalid(tnr_axi_bvalid),
            .s_axi_bready(tnr_axi_bready),
            .s_axi_araddr(tnr_axi_araddr),
            .s_axi_arvalid(tnr_axi_arvalid),
            .s_axi_arready(tnr_axi_arready),
            .s_axi_rdata(tnr_axi_rdata),
            .s_axi_rresp(tnr_axi_rresp),
            .s_axi_rvalid(tnr_axi_rvalid),
            .s_axi_rready(tnr_axi_rready),
            .m_axi_awaddr(tnr_mem_awaddr),
            .m_axi_awlen(tnr_mem_awlen),
            .m_axi_awvalid(tnr_mem_awvalid),
            .m_axi_awready(tnr_mem_awready),
            .m_axi_wdata(tnr_mem_wdata),
            .m_axi_wstrb(tnr_mem_wstrb),
            .m_axi_wlast(tnr_mem_wlast),
            .m_axi_wvalid(tnr_mem_wvalid),
            .m_axi_wready(tnr_mem_wready),
            .m_axi_bresp(tnr_mem_bresp),
            .m_axi_bvalid(tnr_mem_bvalid),
            .m_axi_bready(tnr_mem_bready),
            .m_axi_araddr(tnr_mem_araddr),
            .m_axi_arlen(tnr_mem_arlen),
            .m_axi_arvalid(tnr_mem_arvalid),
            .m_axi_arready(tnr_mem_arready),
            .m_axi_rdata(tnr_mem_rdata),
            .m_axi_rresp(tnr_mem_rresp),
            .m_axi_rlast(tnr_mem_rlast),
            .m_axi_rvalid(tnr_mem_rvalid),
            .m_axi_rready(tnr_mem_rready)
        );
        assign m_packet_error=1'b0;
    end else begin: NO_TEMPORAL
        assign m_data=pre_tnr_data;
        assign m_valid=pre_tnr_valid;
        assign m_sof=pre_tnr_sof;
        assign m_eol=pre_tnr_eol;
        assign m_packet_error=pre_tnr_packet;
        assign m_global_fault=pre_tnr_fault;
        assign tnr_axi_awready=1'b0;
        assign tnr_axi_wready=1'b0;
        assign tnr_axi_bresp=2'b0;
        assign tnr_axi_bvalid=1'b0;
        assign tnr_axi_arready=1'b0;
        assign tnr_axi_rdata=32'b0;
        assign tnr_axi_rresp=2'b0;
        assign tnr_axi_rvalid=1'b0;
        assign tnr_mem_awaddr=32'b0;
        assign tnr_mem_awlen=8'b0;
        assign tnr_mem_awvalid=1'b0;
        assign tnr_mem_wdata=128'b0;
        assign tnr_mem_wstrb=16'b0;
        assign tnr_mem_wlast=1'b0;
        assign tnr_mem_wvalid=1'b0;
        assign tnr_mem_bready=1'b0;
        assign tnr_mem_araddr=32'b0;
        assign tnr_mem_arlen=8'b0;
        assign tnr_mem_arvalid=1'b0;
        assign tnr_mem_rready=1'b0;
    end

    // Buffered LTM has variable delay and invalidates captures on resync.
    isp_capture_frontend #(.USE_LTM(USE_LTM),.RUNTIME_CONFIG(ISP_RUNTIME),.WIDTH(LINE_WORDS*2),.HEIGHT(FRAME_LINES)) converter (.ibex_stats_o(ibex_stats_o), .ibex_cfg_reset_ni(ibex_cfg_reset_ni),
        .isp_axi_awaddr(isp_axi_awaddr),
        .isp_axi_awvalid(isp_axi_awvalid),
        .isp_axi_awready(isp_axi_awready),
        .isp_axi_wdata(isp_axi_wdata),
        .isp_axi_wstrb(isp_axi_wstrb),
        .isp_axi_wvalid(isp_axi_wvalid),
        .isp_axi_wready(isp_axi_wready),
        .isp_axi_bresp(isp_axi_bresp),
        .isp_axi_bvalid(isp_axi_bvalid),
        .isp_axi_bready(isp_axi_bready),
        .isp_axi_araddr(isp_axi_araddr),
        .isp_axi_arvalid(isp_axi_arvalid),
        .isp_axi_arready(isp_axi_arready),
        .isp_axi_rdata(isp_axi_rdata),
        .isp_axi_rresp(isp_axi_rresp),
        .isp_axi_rvalid(isp_axi_rvalid),
        .isp_axi_rready(isp_axi_rready),
        .clk     (clk),
        .resetn  (resetn),
        .s_data  (s_data),
        .s_valid (s_valid),
        .s_sof   (s_sof),
        .s_eol   (s_eol),
        .s_packet_error(packet_error),
        .s_global_fault(global_fault),
        .m_data  (pre_tnr_data),
        .m_valid (pre_tnr_valid),
        .m_sof   (pre_tnr_sof),
        .m_eol   (pre_tnr_eol),
        .m_packet_error(pre_tnr_packet),
        .m_global_fault(pre_tnr_fault),
        .m_fault(),.fault_count(),.fifo_level()
    );

    end endgenerate
endmodule
