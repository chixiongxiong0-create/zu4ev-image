`timescale 1ns/1ps
module camera_top (
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
    inout wire [1:0] c0_ddr4_dqs_c,
    input wire pl_clk_p, pl_clk_n,
    input wire mipi_clk_p, mipi_clk_n,
    input wire [1:0] mipi_data_p, mipi_data_n,
    inout wire camera_scl, camera_sda
);
    wire [94:0] gi;
    wire [94:0] go;
    wire [94:0] gt;
    wire [31:0] cap_awaddr;
    wire [31:0] cap_araddr;
    wire [31:0] cap_wdata;
    wire [31:0] cap_rdata;
    wire [31:0] yuy2_data;
    wire [3:0] cap_wstrb;
    wire [1:0] cap_bresp;
    wire [1:0] cap_rresp;
    wire  cap_awvalid;
    wire  cap_awready;
    wire  cap_wvalid;
    wire  cap_wready;
    wire  cap_bvalid;
    wire  cap_bready;
    wire  cap_arvalid;
    wire  cap_arready;
    wire  cap_rvalid;
    wire  cap_rready;
    wire  yuy2_valid;
    wire  yuy2_ready;
    wire  yuy2_sof;
    wire  yuy2_eol;
    wire  cap_irq;
    wire  ps_resetn;
    wire  uvc_resetn;
    wire  dma_awvalid;
    wire  dma_awready;
    wire  dma_wvalid;
    wire  dma_wready;
    wire  dma_wlast;
    wire  dma_bvalid;
    wire  dma_bready;
    wire [15:0] dma_wstrb;
    wire [1:0] dma_bresp;
    wire [31:0] cap1_awaddr;
    wire [31:0] cap1_araddr;
    wire [31:0] cap1_wdata;
    wire [31:0] cap1_rdata;
    wire [31:0] yuy2_1_data;
    wire [3:0] cap1_wstrb;
    wire [1:0] cap1_bresp;
    wire [1:0] cap1_rresp;
    wire  cap1_awvalid;
    wire  cap1_awready;
    wire  cap1_wvalid;
    wire  cap1_wready;
    wire  cap1_bvalid;
    wire  cap1_bready;
    wire  cap1_arvalid;
    wire  cap1_arready;
    wire  cap1_rvalid;
    wire  cap1_rready;
    wire  yuy2_1_valid;
    wire  yuy2_1_ready;
    wire  yuy2_1_sof;
    wire  yuy2_1_eol;
    wire  cap1_irq;
    wire  dma1_awvalid;
    wire  dma1_awready;
    wire  dma1_wvalid;
    wire  dma1_wready;
    wire  dma1_wlast;
    wire  dma1_bvalid;
    wire  dma1_bready;
    wire [15:0] dma1_wstrb;
    wire [1:0] dma1_bresp;
    wire [31:0] raw_cap_awaddr;
    wire [31:0] raw_cap_araddr;
    wire [31:0] raw_cap_wdata;
    wire [31:0] raw_cap_rdata;
    wire [31:0] raw_axis_data;
    wire [3:0] raw_cap_wstrb;
    wire [1:0] raw_cap_bresp;
    wire [1:0] raw_cap_rresp;
    wire  raw_cap_awvalid;
    wire  raw_cap_awready;
    wire  raw_cap_wvalid;
    wire  raw_cap_wready;
    wire  raw_cap_bvalid;
    wire  raw_cap_bready;
    wire  raw_cap_arvalid;
    wire  raw_cap_arready;
    wire  raw_cap_rvalid;
    wire  raw_cap_rready;
    wire  raw_axis_valid;
    wire  raw_axis_ready;
    wire  raw_axis_sof;
    wire  raw_axis_eol;
    wire  raw_cap_irq;
    wire  raw_dma_awvalid;
    wire  raw_dma_awready;
    wire  raw_dma_wvalid;
    wire  raw_dma_wready;
    wire  raw_dma_wlast;
    wire  raw_dma_bvalid;
    wire  raw_dma_bready;
    wire [15:0] raw_dma_wstrb;
    wire [1:0] raw_dma_bresp;
    wire [31:0] isp_axi_awaddr;
    wire  isp_axi_awvalid;
    wire  isp_axi_awready;
    wire [31:0] isp_axi_wdata;
    wire [3:0] isp_axi_wstrb;
    wire  isp_axi_wvalid;
    wire  isp_axi_wready;
    wire [1:0] isp_axi_bresp;
    wire  isp_axi_bvalid;
    wire  isp_axi_bready;
    wire [31:0] isp_axi_araddr;
    wire  isp_axi_arvalid;
    wire  isp_axi_arready;
    wire [31:0] isp_axi_rdata;
    wire [1:0] isp_axi_rresp;
    wire  isp_axi_rvalid;
    wire  isp_axi_rready;
    wire [31:0] tnr_axi_awaddr;
    wire  tnr_axi_awvalid;
    wire  tnr_axi_awready;
    wire [31:0] tnr_axi_wdata;
    wire [3:0] tnr_axi_wstrb;
    wire  tnr_axi_wvalid;
    wire  tnr_axi_wready;
    wire [1:0] tnr_axi_bresp;
    wire  tnr_axi_bvalid;
    wire  tnr_axi_bready;
    wire [31:0] tnr_axi_araddr;
    wire  tnr_axi_arvalid;
    wire  tnr_axi_arready;
    wire [31:0] tnr_axi_rdata;
    wire [1:0] tnr_axi_rresp;
    wire  tnr_axi_rvalid;
    wire  tnr_axi_rready;
    wire [31:0] tnr_mem_awaddr;
    wire [7:0] tnr_mem_awlen;
    wire  tnr_mem_awvalid;
    wire  tnr_mem_awready;
    wire [127:0] tnr_mem_wdata;
    wire [15:0] tnr_mem_wstrb;
    wire  tnr_mem_wlast;
    wire  tnr_mem_wvalid;
    wire  tnr_mem_wready;
    wire [1:0] tnr_mem_bresp;
    wire  tnr_mem_bvalid;
    wire  tnr_mem_bready;
    wire [31:0] tnr_mem_araddr;
    wire [7:0] tnr_mem_arlen;
    wire  tnr_mem_arvalid;
    wire  tnr_mem_arready;
    wire [127:0] tnr_mem_rdata;
    wire [1:0] tnr_mem_rresp;
    wire  tnr_mem_rlast;
    wire  tnr_mem_rvalid;
    wire  tnr_mem_rready;
    wire  tnr_calib_done;
    wire  video_clk;
    wire  lite_clk;
    wire  locked;
    wire  video_resetn;
    wire  rx_lite_resetn;
    wire  rx_video_resetn;
    wire  capture_resetn;
    wire  init_done;
    wire  bus_error;
    wire [31:0] config_reg;
    wire [31:0] status_reg;
    wire [31:0] interrupt_status;
    wire [31:0] interrupt_enable;
    wire [31:0] lane0_info;
    wire [31:0] lane1_info;
    wire [23:0] csi_data;
    wire [95:0] csi_user;
    wire  valid;
    wire  eol;
    wire  sof;
    wire  phy_locked;
    wire  frame_pulse;
    wire ae_fe_irq;
    wire camera_scl_sample, camera_sda_sample;
    wire [15:0] ae_fe_seq;
    wire [13:0] ae_sof_seq;
    wire [15:0] ae_fe_gray;
    wire [13:0] ae_sof_gray;
    wire [63:0] ae_fe_time, ae_sof_time;
    wire  irq;
    wire  phy_reset;
    wire [1:0] phy_fault_sync;
    wire [31:0] converted;
    wire cv,cs,ce,packet_d,fault_d;
    platform platform (
        .c0_ddr4_adr(c0_ddr4_adr),
        .pl_clk_n(pl_clk_n),
        .go(go),
        .gt(gt),
        .ps_resetn(ps_resetn),
        .uvc_resetn(uvc_resetn),
        .tnr_mem_awaddr(tnr_mem_awaddr),
        .tnr_mem_awlen(tnr_mem_awlen),
        .tnr_mem_awvalid(tnr_mem_awvalid),
        .tnr_mem_awready(tnr_mem_awready),
        .tnr_mem_wdata(tnr_mem_wdata),
        .tnr_mem_wstrb(tnr_mem_wstrb),
        .tnr_mem_wlast(tnr_mem_wlast),
        .tnr_mem_wvalid(tnr_mem_wvalid),
        .tnr_mem_wready(tnr_mem_wready),
        .tnr_mem_bresp(tnr_mem_bresp),
        .tnr_mem_bvalid(tnr_mem_bvalid),
        .tnr_mem_bready(tnr_mem_bready),
        .tnr_mem_araddr(tnr_mem_araddr),
        .tnr_mem_arlen(tnr_mem_arlen),
        .tnr_mem_arvalid(tnr_mem_arvalid),
        .tnr_mem_arready(tnr_mem_arready),
        .tnr_mem_rdata(tnr_mem_rdata),
        .tnr_mem_rresp(tnr_mem_rresp),
        .tnr_mem_rlast(tnr_mem_rlast),
        .tnr_mem_rvalid(tnr_mem_rvalid),
        .tnr_mem_rready(tnr_mem_rready),
        .tnr_calib_done(tnr_calib_done),
        .video_clk(video_clk),
        .lite_clk(lite_clk),
        .locked(locked),
        .video_resetn(video_resetn),
        .rx_lite_resetn(rx_lite_resetn),
        .rx_video_resetn(rx_video_resetn),
        .capture_resetn(capture_resetn),
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
        .pl_clk_p(pl_clk_p)
    );
`ifdef SC130_NV12
    wire [31:0] nv_ctrl_awaddr;
    wire nv_ctrl_awvalid;
    wire nv_ctrl_awready;
    wire [31:0] nv_ctrl_wdata;
    wire [3:0] nv_ctrl_wstrb;
    wire nv_ctrl_wvalid;
    wire nv_ctrl_wready;
    wire [1:0] nv_ctrl_bresp;
    wire nv_ctrl_bvalid;
    wire nv_ctrl_bready;
    wire [31:0] nv_ctrl_araddr;
    wire nv_ctrl_arvalid;
    wire nv_ctrl_arready;
    wire [31:0] nv_ctrl_rdata;
    wire [1:0] nv_ctrl_rresp;
    wire nv_ctrl_rvalid;
    wire nv_ctrl_rready;
    wire [31:0] nv_mem_awaddr;
    wire [7:0] nv_mem_awlen;
    wire [2:0] nv_mem_awsize;
    wire [1:0] nv_mem_awburst;
    wire nv_mem_awvalid;
    wire nv_mem_awready;
    wire [127:0] nv_mem_wdata;
    wire [15:0] nv_mem_wstrb;
    wire nv_mem_wlast;
    wire nv_mem_wvalid;
    wire nv_mem_wready;
    wire [1:0] nv_mem_bresp;
    wire nv_mem_bvalid;
    wire nv_mem_bready;
    wire nv_irq;
`endif
    soc_subsystem soc_subsystem (
`ifdef SC130_NV12
        .nv_ctrl_awaddr(nv_ctrl_awaddr),
        .nv_ctrl_awvalid(nv_ctrl_awvalid),
        .nv_ctrl_awready(nv_ctrl_awready),
        .nv_ctrl_wdata(nv_ctrl_wdata),
        .nv_ctrl_wstrb(nv_ctrl_wstrb),
        .nv_ctrl_wvalid(nv_ctrl_wvalid),
        .nv_ctrl_wready(nv_ctrl_wready),
        .nv_ctrl_bresp(nv_ctrl_bresp),
        .nv_ctrl_bvalid(nv_ctrl_bvalid),
        .nv_ctrl_bready(nv_ctrl_bready),
        .nv_ctrl_araddr(nv_ctrl_araddr),
        .nv_ctrl_arvalid(nv_ctrl_arvalid),
        .nv_ctrl_arready(nv_ctrl_arready),
        .nv_ctrl_rdata(nv_ctrl_rdata),
        .nv_ctrl_rresp(nv_ctrl_rresp),
        .nv_ctrl_rvalid(nv_ctrl_rvalid),
        .nv_ctrl_rready(nv_ctrl_rready),
        .nv_mem_awaddr(nv_mem_awaddr),
        .nv_mem_awlen(nv_mem_awlen),
        .nv_mem_awsize(nv_mem_awsize),
        .nv_mem_awburst(nv_mem_awburst),
        .nv_mem_awvalid(nv_mem_awvalid),
        .nv_mem_awready(nv_mem_awready),
        .nv_mem_wdata(nv_mem_wdata),
        .nv_mem_wstrb(nv_mem_wstrb),
        .nv_mem_wlast(nv_mem_wlast),
        .nv_mem_wvalid(nv_mem_wvalid),
        .nv_mem_wready(nv_mem_wready),
        .nv_mem_bresp(nv_mem_bresp),
        .nv_mem_bvalid(nv_mem_bvalid),
        .nv_mem_bready(nv_mem_bready),
        .nv_irq(nv_irq),
`endif
        .camera_sda(camera_sda),
        .camera_scl_sample(camera_scl_sample),
        .ibex_sensor_grant(ibex_sensor_grant),
        .ibex_sensor_scl_low(ibex_sensor_scl_low), .ibex_sensor_sda_low(ibex_sensor_sda_low),
        .ps_sensor_scl_release(ps_sensor_scl_release), .ps_sensor_sda_release(ps_sensor_sda_release),
        .camera_sda_sample(camera_sda_sample),
        .gi(gi),
        .go(go),
        .gt(gt),
        .cap_awaddr(cap_awaddr),
        .cap_araddr(cap_araddr),
        .cap_wdata(cap_wdata),
        .cap_rdata(cap_rdata),
        .yuy2_data(yuy2_data),
        .cap_wstrb(cap_wstrb),
        .cap_bresp(cap_bresp),
        .cap_rresp(cap_rresp),
        .cap_awvalid(cap_awvalid),
        .cap_awready(cap_awready),
        .cap_wvalid(cap_wvalid),
        .cap_wready(cap_wready),
        .cap_bvalid(cap_bvalid),
        .cap_bready(cap_bready),
        .cap_arvalid(cap_arvalid),
        .cap_arready(cap_arready),
        .cap_rvalid(cap_rvalid),
        .cap_rready(cap_rready),
        .yuy2_valid(yuy2_valid),
        .yuy2_ready(yuy2_ready),
        .yuy2_sof(yuy2_sof),
        .yuy2_eol(yuy2_eol),
        .cap_irq(cap_irq),
        .ae_irq(ae_fe_irq),
        .ps_resetn(ps_resetn),
        .uvc_resetn(uvc_resetn),
        .dma_awvalid(dma_awvalid),
        .dma_awready(dma_awready),
        .dma_wvalid(dma_wvalid),
        .dma_wready(dma_wready),
        .dma_wlast(dma_wlast),
        .dma_bvalid(dma_bvalid),
        .dma_bready(dma_bready),
        .dma_wstrb(dma_wstrb),
        .dma_bresp(dma_bresp),
        .cap1_awaddr(cap1_awaddr),
        .cap1_araddr(cap1_araddr),
        .cap1_wdata(cap1_wdata),
        .cap1_rdata(cap1_rdata),
        .yuy2_1_data(yuy2_1_data),
        .cap1_wstrb(cap1_wstrb),
        .cap1_bresp(cap1_bresp),
        .cap1_rresp(cap1_rresp),
        .cap1_awvalid(cap1_awvalid),
        .cap1_awready(cap1_awready),
        .cap1_wvalid(cap1_wvalid),
        .cap1_wready(cap1_wready),
        .cap1_bvalid(cap1_bvalid),
        .cap1_bready(cap1_bready),
        .cap1_arvalid(cap1_arvalid),
        .cap1_arready(cap1_arready),
        .cap1_rvalid(cap1_rvalid),
        .cap1_rready(cap1_rready),
        .yuy2_1_valid(yuy2_1_valid),
        .yuy2_1_ready(yuy2_1_ready),
        .yuy2_1_sof(yuy2_1_sof),
        .yuy2_1_eol(yuy2_1_eol),
        .cap1_irq(cap1_irq),
        .dma1_awvalid(dma1_awvalid),
        .dma1_awready(dma1_awready),
        .dma1_wvalid(dma1_wvalid),
        .dma1_wready(dma1_wready),
        .dma1_wlast(dma1_wlast),
        .dma1_bvalid(dma1_bvalid),
        .dma1_bready(dma1_bready),
        .dma1_wstrb(dma1_wstrb),
        .dma1_bresp(dma1_bresp),
        .raw_cap_awaddr(raw_cap_awaddr),
        .raw_cap_araddr(raw_cap_araddr),
        .raw_cap_wdata(raw_cap_wdata),
        .raw_cap_rdata(raw_cap_rdata),
        .raw_axis_data(raw_axis_data),
        .raw_cap_wstrb(raw_cap_wstrb),
        .raw_cap_bresp(raw_cap_bresp),
        .raw_cap_rresp(raw_cap_rresp),
        .raw_cap_awvalid(raw_cap_awvalid),
        .raw_cap_awready(raw_cap_awready),
        .raw_cap_wvalid(raw_cap_wvalid),
        .raw_cap_wready(raw_cap_wready),
        .raw_cap_bvalid(raw_cap_bvalid),
        .raw_cap_bready(raw_cap_bready),
        .raw_cap_arvalid(raw_cap_arvalid),
        .raw_cap_arready(raw_cap_arready),
        .raw_cap_rvalid(raw_cap_rvalid),
        .raw_cap_rready(raw_cap_rready),
        .raw_axis_valid(raw_axis_valid),
        .raw_axis_ready(raw_axis_ready),
        .raw_axis_sof(raw_axis_sof),
        .raw_axis_eol(raw_axis_eol),
        .raw_cap_irq(raw_cap_irq),
        .raw_dma_awvalid(raw_dma_awvalid),
        .raw_dma_awready(raw_dma_awready),
        .raw_dma_wvalid(raw_dma_wvalid),
        .raw_dma_wready(raw_dma_wready),
        .raw_dma_wlast(raw_dma_wlast),
        .raw_dma_bvalid(raw_dma_bvalid),
        .raw_dma_bready(raw_dma_bready),
        .raw_dma_wstrb(raw_dma_wstrb),
        .raw_dma_bresp(raw_dma_bresp),
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
        .tnr_axi_awaddr(tnr_axi_awaddr),
        .tnr_axi_awvalid(tnr_axi_awvalid),
        .tnr_axi_awready(tnr_axi_awready),
        .tnr_axi_wdata(tnr_axi_wdata),
        .tnr_axi_wstrb(tnr_axi_wstrb),
        .tnr_axi_wvalid(tnr_axi_wvalid),
        .tnr_axi_wready(tnr_axi_wready),
        .tnr_axi_bresp(tnr_axi_bresp),
        .tnr_axi_bvalid(tnr_axi_bvalid),
        .tnr_axi_bready(tnr_axi_bready),
        .tnr_axi_araddr(tnr_axi_araddr),
        .tnr_axi_arvalid(tnr_axi_arvalid),
        .tnr_axi_arready(tnr_axi_arready),
        .tnr_axi_rdata(tnr_axi_rdata),
        .tnr_axi_rresp(tnr_axi_rresp),
        .tnr_axi_rvalid(tnr_axi_rvalid),
        .tnr_axi_rready(tnr_axi_rready),
        .video_clk(video_clk),
        .camera_scl(camera_scl)
    );
    sensor_rx sensor_rx (
        .mipi_clk_n(mipi_clk_n),
        .mipi_data_n(mipi_data_n),
        .video_clk(video_clk),
        .lite_clk(lite_clk),
        .rx_lite_resetn(rx_lite_resetn),
        .rx_video_resetn(rx_video_resetn),
        .init_done(init_done),
        .bus_error(bus_error),
        .config_reg(config_reg),
        .status_reg(status_reg),
        .interrupt_status(interrupt_status),
        .interrupt_enable(interrupt_enable),
        .lane0_info(lane0_info),
        .lane1_info(lane1_info),
        .csi_data(csi_data),
        .csi_user(csi_user),
        .valid(valid),
        .eol(eol),
        .sof(sof),
        .phy_locked(phy_locked),
        .frame_pulse(frame_pulse),
        .irq(irq),
        .phy_reset(phy_reset),
        .phy_fault_sync(phy_fault_sync),
        .mipi_clk_p(mipi_clk_p),
        .mipi_data_p(mipi_data_p)
    );
    ae_fe_event fe_event (
        .clk(video_clk),
        .resetn(rx_video_resetn),
        .fe_pulse(frame_pulse),
        .sof_pulse(valid & sof),
        .ack_toggle(go[13]),
        .irq(ae_fe_irq),
        .frame_seq(ae_fe_seq),
        .sof_seq(ae_sof_seq),
        .frame_gray(ae_fe_gray),
        .sof_gray(ae_sof_gray),
        .fe_time(ae_fe_time),
        .sof_time(ae_sof_time)
    );
    debug_monitor debug_monitor (
        .camera_sda(camera_sda_sample),
        .gi(gi),
        .go(go),
        .yuy2_data(yuy2_data),
        .yuy2_valid(yuy2_valid),
        .yuy2_ready(yuy2_ready),
        .yuy2_sof(yuy2_sof),
        .yuy2_eol(yuy2_eol),
        .cap_irq(cap_irq),
        .yuy2_1_valid(yuy2_1_valid),
        .cap1_irq(cap1_irq),
        .video_clk(video_clk),
        .locked(locked),
        .video_resetn(video_resetn),
        .rx_lite_resetn(rx_lite_resetn),
        .rx_video_resetn(rx_video_resetn),
        .capture_resetn(capture_resetn),
        .init_done(init_done),
        .bus_error(bus_error),
        .config_reg(config_reg),
        .status_reg(status_reg),
        .interrupt_status(interrupt_status),
        .interrupt_enable(interrupt_enable),
        .lane0_info(lane0_info),
        .lane1_info(lane1_info),
        .csi_data(csi_data),
        .valid(valid),
        .eol(eol),
        .sof(sof),
        .phy_locked(phy_locked),
        .frame_pulse(frame_pulse),
        .ae_fe_irq(ae_fe_irq),
        .ae_fe_seq(ae_fe_gray),
        .ae_sof_seq(ae_sof_gray),
        .ae_fe_time(ae_fe_time),
        .ae_sof_time(ae_sof_time),
        .irq(irq),
        .phy_reset(phy_reset),
        .phy_fault_sync(phy_fault_sync),
        .camera_scl(camera_scl_sample)
    );
`ifdef SC130_UVC
    wire ibex_sensor_owner, ibex_sensor_run, ibex_sensor_stop, ibex_sensor_grant;
    wire ibex_sensor_scl_low, ibex_sensor_sda_low;
    wire ps_sensor_scl_release, ps_sensor_sda_release;
    wire [31:0] ibex_sensor_status;
    wire ibex_cfg_resetn;
    wire [15:0] cpu_isp_axi_awaddr;
    wire cpu_isp_axi_awvalid;
    wire cpu_isp_axi_awready;
    wire [31:0] cpu_isp_axi_wdata;
    wire [3:0] cpu_isp_axi_wstrb;
    wire cpu_isp_axi_wvalid;
    wire cpu_isp_axi_wready;
    wire [1:0] cpu_isp_axi_bresp;
    wire cpu_isp_axi_bvalid;
    wire cpu_isp_axi_bready;
    wire [15:0] cpu_isp_axi_araddr;
    wire cpu_isp_axi_arvalid;
    wire cpu_isp_axi_arready;
    wire [31:0] cpu_isp_axi_rdata;
    wire [1:0] cpu_isp_axi_rresp;
    wire cpu_isp_axi_rvalid;
    wire cpu_isp_axi_rready;
    wire [15:0] shared_isp_axi_awaddr;
    wire shared_isp_axi_awvalid;
    wire shared_isp_axi_awready;
    wire [31:0] shared_isp_axi_wdata;
    wire [3:0] shared_isp_axi_wstrb;
    wire shared_isp_axi_wvalid;
    wire shared_isp_axi_wready;
    wire [1:0] shared_isp_axi_bresp;
    wire shared_isp_axi_bvalid;
    wire shared_isp_axi_bready;
    wire [15:0] shared_isp_axi_araddr;
    wire shared_isp_axi_arvalid;
    wire shared_isp_axi_arready;
    wire [31:0] shared_isp_axi_rdata;
    wire [1:0] shared_isp_axi_rresp;
    wire shared_isp_axi_rvalid;
    wire shared_isp_axi_rready;
    ibex_isp_cfg_owner #(.EnableSensorOwnership(1'b1)) ibex_isp_owner_i (
        .sensor_status_async_i(ibex_sensor_status), .owner_o(ibex_sensor_owner), .run_o(ibex_sensor_run), .stop_o(ibex_sensor_stop),
        .clk_i(video_clk),
        .rst_ni(ibex_cfg_resetn),
        .ps_axi_awaddr(isp_axi_awaddr[15:0]),
        .cpu_axi_awaddr(cpu_isp_axi_awaddr),
        .m_axi_awaddr(shared_isp_axi_awaddr),
        .ps_axi_awvalid(isp_axi_awvalid),
        .cpu_axi_awvalid(cpu_isp_axi_awvalid),
        .m_axi_awvalid(shared_isp_axi_awvalid),
        .ps_axi_awready(isp_axi_awready),
        .cpu_axi_awready(cpu_isp_axi_awready),
        .m_axi_awready(shared_isp_axi_awready),
        .ps_axi_wdata(isp_axi_wdata),
        .cpu_axi_wdata(cpu_isp_axi_wdata),
        .m_axi_wdata(shared_isp_axi_wdata),
        .ps_axi_wstrb(isp_axi_wstrb),
        .cpu_axi_wstrb(cpu_isp_axi_wstrb),
        .m_axi_wstrb(shared_isp_axi_wstrb),
        .ps_axi_wvalid(isp_axi_wvalid),
        .cpu_axi_wvalid(cpu_isp_axi_wvalid),
        .m_axi_wvalid(shared_isp_axi_wvalid),
        .ps_axi_wready(isp_axi_wready),
        .cpu_axi_wready(cpu_isp_axi_wready),
        .m_axi_wready(shared_isp_axi_wready),
        .ps_axi_bresp(isp_axi_bresp),
        .cpu_axi_bresp(cpu_isp_axi_bresp),
        .m_axi_bresp(shared_isp_axi_bresp),
        .ps_axi_bvalid(isp_axi_bvalid),
        .cpu_axi_bvalid(cpu_isp_axi_bvalid),
        .m_axi_bvalid(shared_isp_axi_bvalid),
        .ps_axi_bready(isp_axi_bready),
        .cpu_axi_bready(cpu_isp_axi_bready),
        .m_axi_bready(shared_isp_axi_bready),
        .ps_axi_araddr(isp_axi_araddr[15:0]),
        .cpu_axi_araddr(cpu_isp_axi_araddr),
        .m_axi_araddr(shared_isp_axi_araddr),
        .ps_axi_arvalid(isp_axi_arvalid),
        .cpu_axi_arvalid(cpu_isp_axi_arvalid),
        .m_axi_arvalid(shared_isp_axi_arvalid),
        .ps_axi_arready(isp_axi_arready),
        .cpu_axi_arready(cpu_isp_axi_arready),
        .m_axi_arready(shared_isp_axi_arready),
        .ps_axi_rdata(isp_axi_rdata),
        .cpu_axi_rdata(cpu_isp_axi_rdata),
        .m_axi_rdata(shared_isp_axi_rdata),
        .ps_axi_rresp(isp_axi_rresp),
        .cpu_axi_rresp(cpu_isp_axi_rresp),
        .m_axi_rresp(shared_isp_axi_rresp),
        .ps_axi_rvalid(isp_axi_rvalid),
        .cpu_axi_rvalid(cpu_isp_axi_rvalid),
        .m_axi_rvalid(shared_isp_axi_rvalid),
        .ps_axi_rready(isp_axi_rready),
        .cpu_axi_rready(cpu_isp_axi_rready),
        .m_axi_rready(shared_isp_axi_rready));
    wire [511:0] ibex_isp_stats;
    isp #(.PIPELINE(1),.USE_LTM(1),.USE_TNR(1),.ISP_RUNTIME(1)) isp (.ibex_stats_o(ibex_isp_stats), .ibex_cfg_reset_ni(ibex_cfg_resetn),
        .clk(video_clk),
        .resetn(uvc_resetn),
        .s_data(csi_data[19:0]),
        .s_valid(valid),
        .s_sof(sof),
        .s_eol(eol),
        .s_ready(),
        .m_data(converted),
        .m_valid(cv),
        .m_sof(cs),
        .m_eol(ce),
        .m_ready(1'b1),
        .tnr_axi_awaddr(tnr_axi_awaddr[15:0]),
        .tnr_axi_awvalid(tnr_axi_awvalid),
        .tnr_axi_awready(tnr_axi_awready),
        .tnr_axi_wdata(tnr_axi_wdata),
        .tnr_axi_wstrb(tnr_axi_wstrb),
        .tnr_axi_wvalid(tnr_axi_wvalid),
        .tnr_axi_wready(tnr_axi_wready),
        .tnr_axi_bresp(tnr_axi_bresp),
        .tnr_axi_bvalid(tnr_axi_bvalid),
        .tnr_axi_bready(tnr_axi_bready),
        .tnr_axi_araddr(tnr_axi_araddr[15:0]),
        .tnr_axi_arvalid(tnr_axi_arvalid),
        .tnr_axi_arready(tnr_axi_arready),
        .tnr_axi_rdata(tnr_axi_rdata),
        .tnr_axi_rresp(tnr_axi_rresp),
        .tnr_axi_rvalid(tnr_axi_rvalid),
        .tnr_axi_rready(tnr_axi_rready),
        .tnr_calib_done(tnr_calib_done),
        .tnr_mem_awaddr(tnr_mem_awaddr),
        .tnr_mem_awlen(tnr_mem_awlen),
        .tnr_mem_awvalid(tnr_mem_awvalid),
        .tnr_mem_awready(tnr_mem_awready),
        .tnr_mem_wdata(tnr_mem_wdata),
        .tnr_mem_wstrb(tnr_mem_wstrb),
        .tnr_mem_wlast(tnr_mem_wlast),
        .tnr_mem_wvalid(tnr_mem_wvalid),
        .tnr_mem_wready(tnr_mem_wready),
        .tnr_mem_bresp(tnr_mem_bresp),
        .tnr_mem_bvalid(tnr_mem_bvalid),
        .tnr_mem_bready(tnr_mem_bready),
        .tnr_mem_araddr(tnr_mem_araddr),
        .tnr_mem_arlen(tnr_mem_arlen),
        .tnr_mem_arvalid(tnr_mem_arvalid),
        .tnr_mem_arready(tnr_mem_arready),
        .tnr_mem_rdata(tnr_mem_rdata),
        .tnr_mem_rresp(tnr_mem_rresp),
        .tnr_mem_rlast(tnr_mem_rlast),
        .tnr_mem_rvalid(tnr_mem_rvalid),
        .tnr_mem_rready(tnr_mem_rready),
        .isp_axi_awaddr(shared_isp_axi_awaddr),
        .isp_axi_awvalid(shared_isp_axi_awvalid),
        .isp_axi_awready(shared_isp_axi_awready),
        .isp_axi_wdata(shared_isp_axi_wdata),
        .isp_axi_wstrb(shared_isp_axi_wstrb),
        .isp_axi_wvalid(shared_isp_axi_wvalid),
        .isp_axi_wready(shared_isp_axi_wready),
        .isp_axi_bresp(shared_isp_axi_bresp),
        .isp_axi_bvalid(shared_isp_axi_bvalid),
        .isp_axi_bready(shared_isp_axi_bready),
        .isp_axi_araddr(shared_isp_axi_araddr),
        .isp_axi_arvalid(shared_isp_axi_arvalid),
        .isp_axi_arready(shared_isp_axi_arready),
        .isp_axi_rdata(shared_isp_axi_rdata),
        .isp_axi_rresp(shared_isp_axi_rresp),
        .isp_axi_rvalid(shared_isp_axi_rvalid),
        .isp_axi_rready(shared_isp_axi_rready),
        .packet_error(valid & csi_user[1]),
        .global_fault(phy_fault_sync[1]|bus_error),
        .m_packet_error(packet_d),
        .m_global_fault(fault_d)
    );
    video_capture video_capture (
        .clk(video_clk),
        .resetn(uvc_resetn),
        .m0_data(yuy2_data),
        .m0_valid(yuy2_valid),
        .m0_sof(yuy2_sof),
        .m0_eol(yuy2_eol),
        .m0_ready(yuy2_ready),
        .d0_awvalid(dma_awvalid),
        .d0_awready(dma_awready),
        .d0_wvalid(dma_wvalid),
        .d0_wready(dma_wready),
        .d0_wlast(dma_wlast),
        .d0_bvalid(dma_bvalid),
        .d0_bready(dma_bready),
        .d0_wstrb(dma_wstrb),
        .d0_bresp(dma_bresp),
        .irq0(cap_irq),
        .c0_s_axi_awaddr(cap_awaddr[7:0]),
        .c0_s_axi_awvalid(cap_awvalid),
        .c0_s_axi_awready(cap_awready),
        .c0_s_axi_wdata(cap_wdata),
        .c0_s_axi_wstrb(cap_wstrb),
        .c0_s_axi_wvalid(cap_wvalid),
        .c0_s_axi_wready(cap_wready),
        .c0_s_axi_bresp(cap_bresp),
        .c0_s_axi_bvalid(cap_bvalid),
        .c0_s_axi_bready(cap_bready),
        .c0_s_axi_araddr(cap_araddr[7:0]),
        .c0_s_axi_arvalid(cap_arvalid),
        .c0_s_axi_arready(cap_arready),
        .c0_s_axi_rdata(cap_rdata),
        .c0_s_axi_rresp(cap_rresp),
        .c0_s_axi_rvalid(cap_rvalid),
        .c0_s_axi_rready(cap_rready),
        .m1_data(yuy2_1_data),
        .m1_valid(yuy2_1_valid),
        .m1_sof(yuy2_1_sof),
        .m1_eol(yuy2_1_eol),
        .m1_ready(yuy2_1_ready),
        .d1_awvalid(dma1_awvalid),
        .d1_awready(dma1_awready),
        .d1_wvalid(dma1_wvalid),
        .d1_wready(dma1_wready),
        .d1_wlast(dma1_wlast),
        .d1_bvalid(dma1_bvalid),
        .d1_bready(dma1_bready),
        .d1_wstrb(dma1_wstrb),
        .d1_bresp(dma1_bresp),
        .irq1(cap1_irq),
        .c1_s_axi_awaddr(cap1_awaddr[7:0]),
        .c1_s_axi_awvalid(cap1_awvalid),
        .c1_s_axi_awready(cap1_awready),
        .c1_s_axi_wdata(cap1_wdata),
        .c1_s_axi_wstrb(cap1_wstrb),
        .c1_s_axi_wvalid(cap1_wvalid),
        .c1_s_axi_wready(cap1_wready),
        .c1_s_axi_bresp(cap1_bresp),
        .c1_s_axi_bvalid(cap1_bvalid),
        .c1_s_axi_bready(cap1_bready),
        .c1_s_axi_araddr(cap1_araddr[7:0]),
        .c1_s_axi_arvalid(cap1_arvalid),
        .c1_s_axi_arready(cap1_arready),
        .c1_s_axi_rdata(cap1_rdata),
        .c1_s_axi_rresp(cap1_rresp),
        .c1_s_axi_rvalid(cap1_rvalid),
        .c1_s_axi_rready(cap1_rready),
        .converted(converted),
        .cv(cv),
        .cs(cs),
        .ce(ce),
        .packet_d(packet_d),
        .fault_d(fault_d)
    );
    raw10_capture raw_capture (
        .clk(video_clk),
        .resetn(uvc_resetn),
        .m0_data(raw_axis_data),
        .m0_valid(raw_axis_valid),
        .m0_sof(raw_axis_sof),
        .m0_eol(raw_axis_eol),
        .m0_ready(raw_axis_ready),
        .d0_awvalid(raw_dma_awvalid),
        .d0_awready(raw_dma_awready),
        .d0_wvalid(raw_dma_wvalid),
        .d0_wready(raw_dma_wready),
        .d0_wlast(raw_dma_wlast),
        .d0_bvalid(raw_dma_bvalid),
        .d0_bready(raw_dma_bready),
        .d0_wstrb(raw_dma_wstrb),
        .d0_bresp(raw_dma_bresp),
        .irq0(raw_cap_irq),
        .c0_s_axi_awaddr(raw_cap_awaddr[7:0]),
        .c0_s_axi_awvalid(raw_cap_awvalid),
        .c0_s_axi_awready(raw_cap_awready),
        .c0_s_axi_wdata(raw_cap_wdata),
        .c0_s_axi_wstrb(raw_cap_wstrb),
        .c0_s_axi_wvalid(raw_cap_wvalid),
        .c0_s_axi_wready(raw_cap_wready),
        .c0_s_axi_bresp(raw_cap_bresp),
        .c0_s_axi_bvalid(raw_cap_bvalid),
        .c0_s_axi_bready(raw_cap_bready),
        .c0_s_axi_araddr(raw_cap_araddr[7:0]),
        .c0_s_axi_arvalid(raw_cap_arvalid),
        .c0_s_axi_arready(raw_cap_arready),
        .c0_s_axi_rdata(raw_cap_rdata),
        .c0_s_axi_rresp(raw_cap_rresp),
        .c0_s_axi_rvalid(raw_cap_rvalid),
        .c0_s_axi_rready(raw_cap_rready),
        .raw_data(csi_data[19:0]),.raw_valid(valid),.raw_sof(sof),.raw_eol(eol),
        .packet_error(valid & csi_user[1]),
        .global_fault(phy_fault_sync[1] | bus_error | !rx_video_resetn)
    );
`endif
    ibex_board_debug ibex_debug_i (.clk_i(lite_clk), .locked_i(locked), .video_clk_i(video_clk), .video_rst_ni(rx_video_resetn), .isp_stats_i(ibex_isp_stats), .isp_fe_seq_i(ae_fe_seq), .isp_sof_seq_i(ae_sof_seq), .sensor_owner_i(ibex_sensor_owner), .sensor_run_i(ibex_sensor_run), .sensor_stop_i(ibex_sensor_stop), .sensor_ps_scl_release_i(ps_sensor_scl_release), .sensor_ps_sda_release_i(ps_sensor_sda_release), .sensor_scl_i(camera_scl_sample), .sensor_sda_i(camera_sda_sample), .sensor_scl_low_o(ibex_sensor_scl_low), .sensor_sda_low_o(ibex_sensor_sda_low), .sensor_grant_o(ibex_sensor_grant), .sensor_status_o(ibex_sensor_status), .isp_cfg_rst_ni(uvc_resetn), .cfg_reset_no(ibex_cfg_resetn), .m_isp_axi_awaddr(cpu_isp_axi_awaddr), .m_isp_axi_awvalid(cpu_isp_axi_awvalid), .m_isp_axi_awready(cpu_isp_axi_awready), .m_isp_axi_wdata(cpu_isp_axi_wdata), .m_isp_axi_wstrb(cpu_isp_axi_wstrb), .m_isp_axi_wvalid(cpu_isp_axi_wvalid), .m_isp_axi_wready(cpu_isp_axi_wready), .m_isp_axi_bresp(cpu_isp_axi_bresp), .m_isp_axi_bvalid(cpu_isp_axi_bvalid), .m_isp_axi_bready(cpu_isp_axi_bready), .m_isp_axi_araddr(cpu_isp_axi_araddr), .m_isp_axi_arvalid(cpu_isp_axi_arvalid), .m_isp_axi_arready(cpu_isp_axi_arready), .m_isp_axi_rdata(cpu_isp_axi_rdata), .m_isp_axi_rresp(cpu_isp_axi_rresp), .m_isp_axi_rvalid(cpu_isp_axi_rvalid), .m_isp_axi_rready(cpu_isp_axi_rready));

`ifdef SC130_NV12
    // Parallel output after final TNR; no backpressure into the ISP/DP path.
    nv12_capture_peripheral nv12_output (
        .clk(video_clk),.resetn(uvc_resetn),
        .s_data(converted),.s_valid(cv),.s_sof(cs),.s_eol(ce),
        .s_fault(packet_d | fault_d),.irq(nv_irq),
        .s_axi_awaddr(nv_ctrl_awaddr[7:0]),
        .s_axi_awvalid(nv_ctrl_awvalid),
        .s_axi_awready(nv_ctrl_awready),
        .s_axi_wdata(nv_ctrl_wdata),
        .s_axi_wstrb(nv_ctrl_wstrb),
        .s_axi_wvalid(nv_ctrl_wvalid),
        .s_axi_wready(nv_ctrl_wready),
        .s_axi_bresp(nv_ctrl_bresp),
        .s_axi_bvalid(nv_ctrl_bvalid),
        .s_axi_bready(nv_ctrl_bready),
        .s_axi_araddr(nv_ctrl_araddr[7:0]),
        .s_axi_arvalid(nv_ctrl_arvalid),
        .s_axi_arready(nv_ctrl_arready),
        .s_axi_rdata(nv_ctrl_rdata),
        .s_axi_rresp(nv_ctrl_rresp),
        .s_axi_rvalid(nv_ctrl_rvalid),
        .s_axi_rready(nv_ctrl_rready),
        .m_axi_awaddr(nv_mem_awaddr),
        .m_axi_awlen(nv_mem_awlen),
        .m_axi_awsize(nv_mem_awsize),
        .m_axi_awburst(nv_mem_awburst),
        .m_axi_awvalid(nv_mem_awvalid),
        .m_axi_awready(nv_mem_awready),
        .m_axi_wdata(nv_mem_wdata),
        .m_axi_wstrb(nv_mem_wstrb),
        .m_axi_wlast(nv_mem_wlast),
        .m_axi_wvalid(nv_mem_wvalid),
        .m_axi_wready(nv_mem_wready),
        .m_axi_bresp(nv_mem_bresp),
        .m_axi_bvalid(nv_mem_bvalid),
        .m_axi_bready(nv_mem_bready)
    );
`endif
endmodule
