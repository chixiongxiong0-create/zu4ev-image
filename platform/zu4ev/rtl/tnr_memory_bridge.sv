`timescale 1ns/1ps
// Video-domain AXI to the independent MIG UI domain. IDs are fixed at zero.
module tnr_memory_bridge (
    input wire ref_clk, clock_locked, video_clk, video_resetn,
    output wire calib_done,
    input wire [31:0] s_axi_awaddr,
    input wire [7:0] s_axi_awlen,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    input wire [127:0] s_axi_wdata,
    input wire [15:0] s_axi_wstrb,
    input wire s_axi_wlast,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    output wire [1:0] s_axi_bresp,
    output wire s_axi_bvalid,
    input wire s_axi_bready,
    input wire [31:0] s_axi_araddr,
    input wire [7:0] s_axi_arlen,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    output wire [127:0] s_axi_rdata,
    output wire [1:0] s_axi_rresp,
    output wire s_axi_rlast,
    output wire s_axi_rvalid,
    input wire s_axi_rready,
    output wire [16:0] c0_ddr4_adr,
    output wire [1:0] c0_ddr4_ba,
    output wire [0:0] c0_ddr4_bg,
    output wire [0:0] c0_ddr4_cke,
    output wire [0:0] c0_ddr4_cs_n,
    output wire [0:0] c0_ddr4_odt,
    output wire [0:0] c0_ddr4_ck_t,
    output wire [0:0] c0_ddr4_ck_c,
    output wire c0_ddr4_act_n,
    output wire c0_ddr4_reset_n,
    inout wire [15:0] c0_ddr4_dq,
    inout wire [1:0] c0_ddr4_dm_dbi_n,
    inout wire [1:0] c0_ddr4_dqs_t,
    inout wire [1:0] c0_ddr4_dqs_c
);
    wire ui_clk, ui_reset, calibrated;
    (* ASYNC_REG="TRUE" *) reg [1:0] ui_resetn_sync=0;
    (* ASYNC_REG="TRUE" *) reg [1:0] calibration_sync=0;
    // Asynchronously assert both AXI domains on video reset. UI release is local.
    always @(posedge ui_clk or negedge video_resetn or posedge ui_reset)
        if(!video_resetn || ui_reset) ui_resetn_sync<=0;
        else ui_resetn_sync<={ui_resetn_sync[0],1'b1};
    always @(posedge video_clk or negedge video_resetn)
        if(!video_resetn) calibration_sync<=0;
        else calibration_sync<={calibration_sync[0],calibrated};
    assign calib_done=calibration_sync[1];
    wire [31:0] ui_awaddr;
    wire [7:0] ui_awlen;
    wire ui_awvalid;
    wire ui_awready;
    wire [127:0] ui_wdata;
    wire [15:0] ui_wstrb;
    wire ui_wlast;
    wire ui_wvalid;
    wire ui_wready;
    wire [1:0] ui_bresp;
    wire ui_bvalid;
    wire ui_bready;
    wire [31:0] ui_araddr;
    wire [7:0] ui_arlen;
    wire ui_arvalid;
    wire ui_arready;
    wire [127:0] ui_rdata;
    wire [1:0] ui_rresp;
    wire ui_rlast;
    wire ui_rvalid;
    wire ui_rready;
    wire [3:0] ui_awid;
    wire [2:0] ui_awsize;
    wire [1:0] ui_awburst;
    wire ui_awlock;
    wire [3:0] ui_awcache;
    wire [2:0] ui_awprot;
    wire [3:0] ui_awqos;
    wire [3:0] ui_arid;
    wire [2:0] ui_arsize;
    wire [1:0] ui_arburst;
    wire ui_arlock;
    wire [3:0] ui_arcache;
    wire [2:0] ui_arprot;
    wire [3:0] ui_arqos;
    wire [3:0] ui_bid;
    wire [3:0] ui_rid;
    tnr_axi_clock_converter crossing (
        .s_axi_aclk(video_clk),.s_axi_aresetn(video_resetn),
        .m_axi_aclk(ui_clk),.m_axi_aresetn(ui_resetn_sync[1]),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awlen(s_axi_awlen),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wlast(s_axi_wlast),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arlen(s_axi_arlen),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rlast(s_axi_rlast),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .s_axi_awid(4'b0),.s_axi_awsize(3'd4),.s_axi_awburst(2'b01),
        .s_axi_awregion(4'b0),.s_axi_arregion(4'b0),
        .m_axi_awregion(),.m_axi_arregion(),
        .s_axi_awlock(1'b0),.s_axi_awcache(4'b0011),.s_axi_awprot(3'b0),.s_axi_awqos(4'b0),
        .s_axi_arid(4'b0),.s_axi_arsize(3'd4),.s_axi_arburst(2'b01),
        .s_axi_arlock(1'b0),.s_axi_arcache(4'b0011),.s_axi_arprot(3'b0),.s_axi_arqos(4'b0),
        .s_axi_bid(),.s_axi_rid(),
        .m_axi_awaddr(ui_awaddr),
        .m_axi_awlen(ui_awlen),
        .m_axi_awvalid(ui_awvalid),
        .m_axi_awready(ui_awready),
        .m_axi_wdata(ui_wdata),
        .m_axi_wstrb(ui_wstrb),
        .m_axi_wlast(ui_wlast),
        .m_axi_wvalid(ui_wvalid),
        .m_axi_wready(ui_wready),
        .m_axi_bresp(ui_bresp),
        .m_axi_bvalid(ui_bvalid),
        .m_axi_bready(ui_bready),
        .m_axi_araddr(ui_araddr),
        .m_axi_arlen(ui_arlen),
        .m_axi_arvalid(ui_arvalid),
        .m_axi_arready(ui_arready),
        .m_axi_rdata(ui_rdata),
        .m_axi_rresp(ui_rresp),
        .m_axi_rlast(ui_rlast),
        .m_axi_rvalid(ui_rvalid),
        .m_axi_rready(ui_rready),
        .m_axi_awid(ui_awid),
        .m_axi_awsize(ui_awsize),
        .m_axi_awburst(ui_awburst),
        .m_axi_awlock(ui_awlock),
        .m_axi_awcache(ui_awcache),
        .m_axi_awprot(ui_awprot),
        .m_axi_awqos(ui_awqos),
        .m_axi_arid(ui_arid),
        .m_axi_arsize(ui_arsize),
        .m_axi_arburst(ui_arburst),
        .m_axi_arlock(ui_arlock),
        .m_axi_arcache(ui_arcache),
        .m_axi_arprot(ui_arprot),
        .m_axi_arqos(ui_arqos),
        .m_axi_bid(ui_bid),
        .m_axi_rid(ui_rid)
    );
    pl_ddr4 memory (
        .c0_sys_clk_i(ref_clk),.sys_rst(!clock_locked),
        .c0_init_calib_complete(calibrated),.dbg_clk(),.dbg_bus(),
        .c0_ddr4_ui_clk(ui_clk),.c0_ddr4_ui_clk_sync_rst(ui_reset),
        .c0_ddr4_aresetn(ui_resetn_sync[1]),
        .c0_ddr4_adr(c0_ddr4_adr),
        .c0_ddr4_ba(c0_ddr4_ba),
        .c0_ddr4_bg(c0_ddr4_bg),
        .c0_ddr4_cke(c0_ddr4_cke),
        .c0_ddr4_cs_n(c0_ddr4_cs_n),
        .c0_ddr4_odt(c0_ddr4_odt),
        .c0_ddr4_ck_t(c0_ddr4_ck_t),
        .c0_ddr4_ck_c(c0_ddr4_ck_c),
        .c0_ddr4_act_n(c0_ddr4_act_n),
        .c0_ddr4_reset_n(c0_ddr4_reset_n),
        .c0_ddr4_dq(c0_ddr4_dq),
        .c0_ddr4_dm_dbi_n(c0_ddr4_dm_dbi_n),
        .c0_ddr4_dqs_t(c0_ddr4_dqs_t),
        .c0_ddr4_dqs_c(c0_ddr4_dqs_c),
        .c0_ddr4_s_axi_awaddr(ui_awaddr[29:0]),
        .c0_ddr4_s_axi_awlen(ui_awlen),
        .c0_ddr4_s_axi_awvalid(ui_awvalid),
        .c0_ddr4_s_axi_awready(ui_awready),
        .c0_ddr4_s_axi_wdata(ui_wdata),
        .c0_ddr4_s_axi_wstrb(ui_wstrb),
        .c0_ddr4_s_axi_wlast(ui_wlast),
        .c0_ddr4_s_axi_wvalid(ui_wvalid),
        .c0_ddr4_s_axi_wready(ui_wready),
        .c0_ddr4_s_axi_bresp(ui_bresp),
        .c0_ddr4_s_axi_bvalid(ui_bvalid),
        .c0_ddr4_s_axi_bready(ui_bready),
        .c0_ddr4_s_axi_araddr(ui_araddr[29:0]),
        .c0_ddr4_s_axi_arlen(ui_arlen),
        .c0_ddr4_s_axi_arvalid(ui_arvalid),
        .c0_ddr4_s_axi_arready(ui_arready),
        .c0_ddr4_s_axi_rdata(ui_rdata),
        .c0_ddr4_s_axi_rresp(ui_rresp),
        .c0_ddr4_s_axi_rlast(ui_rlast),
        .c0_ddr4_s_axi_rvalid(ui_rvalid),
        .c0_ddr4_s_axi_rready(ui_rready),
        .c0_ddr4_s_axi_awid(ui_awid),
        .c0_ddr4_s_axi_awsize(ui_awsize),
        .c0_ddr4_s_axi_awburst(ui_awburst),
        .c0_ddr4_s_axi_awlock(ui_awlock),
        .c0_ddr4_s_axi_awcache(ui_awcache),
        .c0_ddr4_s_axi_awprot(ui_awprot),
        .c0_ddr4_s_axi_awqos(ui_awqos),
        .c0_ddr4_s_axi_arid(ui_arid),
        .c0_ddr4_s_axi_arsize(ui_arsize),
        .c0_ddr4_s_axi_arburst(ui_arburst),
        .c0_ddr4_s_axi_arlock(ui_arlock),
        .c0_ddr4_s_axi_arcache(ui_arcache),
        .c0_ddr4_s_axi_arprot(ui_arprot),
        .c0_ddr4_s_axi_arqos(ui_arqos),
        .c0_ddr4_s_axi_bid(ui_bid),
        .c0_ddr4_s_axi_rid(ui_rid)
    );
endmodule

