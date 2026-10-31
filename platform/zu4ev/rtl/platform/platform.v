`timescale 1ns/1ps
module platform (
    output wire [16:0] c0_ddr4_adr,
    input wire  pl_clk_n,
    input wire [94:0] go,
    input wire [94:0] gt,
    input wire  ps_resetn,
    output wire  uvc_resetn,
    input wire [31:0] tnr_mem_awaddr,
    input wire [7:0] tnr_mem_awlen,
    input wire  tnr_mem_awvalid,
    output wire  tnr_mem_awready,
    input wire [127:0] tnr_mem_wdata,
    input wire [15:0] tnr_mem_wstrb,
    input wire  tnr_mem_wlast,
    input wire  tnr_mem_wvalid,
    output wire  tnr_mem_wready,
    output wire [1:0] tnr_mem_bresp,
    output wire  tnr_mem_bvalid,
    input wire  tnr_mem_bready,
    input wire [31:0] tnr_mem_araddr,
    input wire [7:0] tnr_mem_arlen,
    input wire  tnr_mem_arvalid,
    output wire  tnr_mem_arready,
    output wire [127:0] tnr_mem_rdata,
    output wire [1:0] tnr_mem_rresp,
    output wire  tnr_mem_rlast,
    output wire  tnr_mem_rvalid,
    input wire  tnr_mem_rready,
    output wire  tnr_calib_done,
    output wire  video_clk,
    output wire  lite_clk,
    output wire  locked,
    output wire  video_resetn,
    output wire  rx_lite_resetn,
    output wire  rx_video_resetn,
    output wire  capture_resetn,
    output wire [1:0] c0_ddr4_ba,
    output wire [0:0] c0_ddr4_bg,
    output wire [0:0] c0_ddr4_cke,
    output wire [0:0] c0_ddr4_cs_n,
    output wire [0:0] c0_ddr4_odt,
    output wire [0:0] c0_ddr4_ck_t,
    output wire [0:0] c0_ddr4_ck_c,
    output wire  c0_ddr4_act_n,
    output wire  c0_ddr4_reset_n,
    inout wire [15:0] c0_ddr4_dq,
    inout wire [1:0] c0_ddr4_dm_dbi_n,
    inout wire [1:0] c0_ddr4_dqs_t,
    inout wire [1:0] c0_ddr4_dqs_c,
    input wire  pl_clk_p
);
    
    wire  pl_ref_clk;
    IBUFDS ref_input (.I(pl_clk_p),.IB(pl_clk_n),.O(pl_ref_clk));
    camera_clocks clocks_i (
        .clk_in1 (pl_ref_clk),
        .reset     (1'b0),
        .locked    (locked),
        .clk_out1  (video_clk),
        .clk_out2  (lite_clk)
    );
    wire  
        lite_resetn;
    camera_reset video_reset_i (
        .clk    (video_clk),
        .locked (locked),
        .resetn (video_resetn)
    );
    camera_reset lite_reset_i (
        .clk    (lite_clk),
        .locked (locked),
        .resetn (lite_resetn)
    );
    
`ifdef SC130_UVC
    camera_pipeline_reset pipeline_reset_i (
        .video_clk(video_clk), .lite_clk(lite_clk), .locked(locked),
        .ps_resetn(ps_resetn),
        .lite_enable(go[16] & ~gt[16]),
        .video_enable(go[17] & ~gt[17]),
        .capture_enable(go[18] & ~gt[18]),
        .lite_resetn(rx_lite_resetn), .video_resetn(rx_video_resetn),
        .capture_resetn(capture_resetn));
`else
    assign rx_lite_resetn = lite_resetn;
    assign rx_video_resetn = video_resetn;
    assign capture_resetn = video_resetn;
`endif

`ifdef SC130_UVC
    assign uvc_resetn = capture_resetn;
    tnr_memory_bridge tnr_memory (
        .ref_clk(pl_ref_clk),.clock_locked(locked),.video_clk(video_clk),.video_resetn(uvc_resetn),
        .calib_done(tnr_calib_done),
        .s_axi_awaddr(tnr_mem_awaddr),
        .s_axi_awlen(tnr_mem_awlen),
        .s_axi_awvalid(tnr_mem_awvalid),
        .s_axi_awready(tnr_mem_awready),
        .s_axi_wdata(tnr_mem_wdata),
        .s_axi_wstrb(tnr_mem_wstrb),
        .s_axi_wlast(tnr_mem_wlast),
        .s_axi_wvalid(tnr_mem_wvalid),
        .s_axi_wready(tnr_mem_wready),
        .s_axi_bresp(tnr_mem_bresp),
        .s_axi_bvalid(tnr_mem_bvalid),
        .s_axi_bready(tnr_mem_bready),
        .s_axi_araddr(tnr_mem_araddr),
        .s_axi_arlen(tnr_mem_arlen),
        .s_axi_arvalid(tnr_mem_arvalid),
        .s_axi_arready(tnr_mem_arready),
        .s_axi_rdata(tnr_mem_rdata),
        .s_axi_rresp(tnr_mem_rresp),
        .s_axi_rlast(tnr_mem_rlast),
        .s_axi_rvalid(tnr_mem_rvalid),
        .s_axi_rready(tnr_mem_rready),
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
        .c0_ddr4_dqs_c(c0_ddr4_dqs_c)
    );
`endif
endmodule
