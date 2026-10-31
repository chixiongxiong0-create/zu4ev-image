// SPDX-License-Identifier: Apache-2.0
// Ibex board integration; configuration ownership is enforced in camera_top.
`ifndef IBEX_BOARD_ROM_FILE
`define IBEX_BOARD_ROM_FILE "ae.mem"
`endif
`ifndef IBEX_BOARD_BOOT_WORDS
`define IBEX_BOARD_BOOT_WORDS 964
`endif
module ibex_board_debug #(parameter RomFile = `IBEX_BOARD_ROM_FILE,
                         parameter int unsigned BootImageWords = `IBEX_BOARD_BOOT_WORDS)(
 input wire isp_cfg_rst_ni,
 input wire sensor_owner_i,sensor_run_i,sensor_stop_i,
 input wire sensor_ps_scl_release_i,sensor_ps_sda_release_i,sensor_scl_i,sensor_sda_i,
 output wire sensor_scl_low_o,sensor_sda_low_o,sensor_grant_o,
 output wire [31:0] sensor_status_o,
 output wire cfg_reset_no,
 output wire [15:0] m_isp_axi_awaddr,
 output wire m_isp_axi_awvalid,
 input wire m_isp_axi_awready,
 output wire [31:0] m_isp_axi_wdata,
 output wire [3:0] m_isp_axi_wstrb,
 output wire m_isp_axi_wvalid,
 input wire m_isp_axi_wready,
 input wire [1:0] m_isp_axi_bresp,
 input wire m_isp_axi_bvalid,
 output wire m_isp_axi_bready,
 output wire [15:0] m_isp_axi_araddr,
 output wire m_isp_axi_arvalid,
 input wire m_isp_axi_arready,
 input wire [31:0] m_isp_axi_rdata,
 input wire [1:0] m_isp_axi_rresp,
 input wire m_isp_axi_rvalid,
 output wire m_isp_axi_rready,
input wire clk_i, locked_i, video_clk_i, video_rst_ni, input wire [511:0] isp_stats_i, input wire [15:0] isp_fe_seq_i, input wire [13:0] isp_sof_seq_i);
  logic [7:0] power_count = 0;
  always_ff @(posedge clk_i or negedge locked_i)
    if (!locked_i) power_count <= 0;
    else if (!(&power_count)) power_count <= power_count + 1'b1;
  wire axi_resetn = &power_count;
  wire cfg_async_reset_n = axi_resetn & isp_cfg_rst_ni;
  (* ASYNC_REG="TRUE" *) logic [1:0] cfg_reset_sync = 0;
  always_ff @(posedge video_clk_i or negedge cfg_async_reset_n)
    if (!cfg_async_reset_n) cfg_reset_sync <= 0;
    else cfg_reset_sync <= {cfg_reset_sync[0],1'b1};
  assign cfg_reset_no = cfg_reset_sync[1];
  (* ASYNC_REG="TRUE" *) logic [1:0] system_reset_sync = 0;
  always_ff @(posedge clk_i or negedge cfg_reset_no)
    if (!cfg_reset_no) system_reset_sync <= 0;
    else system_reset_sync <= {system_reset_sync[0],1'b1};
  wire reset_cpu;
  (* ASYNC_REG="TRUE" *) logic [1:0] reset_sync = 0;
  always_ff @(posedge clk_i or negedge axi_resetn)
    if (!axi_resetn) reset_sync <= 0;
    else reset_sync <= {reset_sync[0], !reset_cpu};
  wire sleep, minor, major_int, major_bus;
  wire [31:0] axi_araddr;
  wire [31:0] axi_awaddr;
  wire [31:0] axi_wdata;
  wire [2:0] axi_arprot;
  wire [2:0] axi_awprot;
  wire [3:0] axi_wstrb;
  wire [0:0] axi_arvalid;
  wire [0:0] axi_rready;
  wire [0:0] axi_awvalid;
  wire [0:0] axi_wvalid;
  wire [0:0] axi_bready;
  wire [0:0] axi_arready;
  wire [0:0] axi_rvalid;
  wire [0:0] axi_awready;
  wire [0:0] axi_wready;
  wire [0:0] axi_bvalid;
  wire [31:0] axi_rdata;
  wire [1:0] axi_rresp;
  wire [1:0] axi_bresp;
  ibex_small_system #(.RomFile(RomFile), .RamPrimitive("ultra"), .ProgramPrimitive("ultra"), .BootImageWords(BootImageWords), .EnableInputMailbox(1'b1), .EnableIspAccess(1'b1), .EnableIspConfig(1'b1), .EnableCpuResetInput(1'b1), .EnableSensorControl(1'b1)) u_system (
    .clk_i(clk_i), .rst_ni(system_reset_sync[1]), .cpu_rst_ni(reset_sync[1]),
    .sensor_owner_i,.sensor_run_i,.sensor_stop_i,.sensor_ps_scl_release_i,.sensor_ps_sda_release_i,
    .sensor_scl_i,.sensor_sda_i,.sensor_scl_low_o,.sensor_sda_low_o,.sensor_grant_o,.sensor_status_o,
    .isp_cfg_clk_i(video_clk_i), .isp_cfg_rst_ni(cfg_reset_no),
    .m_isp_axi_awaddr(m_isp_axi_awaddr),
    .m_isp_axi_awvalid(m_isp_axi_awvalid),
    .m_isp_axi_awready(m_isp_axi_awready),
    .m_isp_axi_wdata(m_isp_axi_wdata),
    .m_isp_axi_wstrb(m_isp_axi_wstrb),
    .m_isp_axi_wvalid(m_isp_axi_wvalid),
    .m_isp_axi_wready(m_isp_axi_wready),
    .m_isp_axi_bresp(m_isp_axi_bresp),
    .m_isp_axi_bvalid(m_isp_axi_bvalid),
    .m_isp_axi_bready(m_isp_axi_bready),
    .m_isp_axi_araddr(m_isp_axi_araddr),
    .m_isp_axi_arvalid(m_isp_axi_arvalid),
    .m_isp_axi_arready(m_isp_axi_arready),
    .m_isp_axi_rdata(m_isp_axi_rdata),
    .m_isp_axi_rresp(m_isp_axi_rresp),
    .m_isp_axi_rvalid(m_isp_axi_rvalid),
    .m_isp_axi_rready(m_isp_axi_rready),

    .video_clk_i, .video_rst_ni(reset_sync[1] & video_rst_ni), .isp_stats_i, .isp_fe_seq_i, .isp_sof_seq_i,
    .irq_software_i(1'b0), .irq_timer_i(1'b0), .irq_external_i(1'b0),
    .irq_fast_i(15'b0), .irq_nm_i(1'b0), .debug_req_i(1'b0),
    .core_sleep_o(sleep), .alert_minor_o(minor), .alert_major_internal_o(major_int), .alert_major_bus_o(major_bus),
    .s_axi_araddr(axi_araddr),
    .s_axi_awaddr(axi_awaddr),
    .s_axi_wdata(axi_wdata),
    .s_axi_arprot(axi_arprot),
    .s_axi_awprot(axi_awprot),
    .s_axi_wstrb(axi_wstrb),
    .s_axi_arvalid(axi_arvalid),
    .s_axi_rready(axi_rready),
    .s_axi_awvalid(axi_awvalid),
    .s_axi_wvalid(axi_wvalid),
    .s_axi_bready(axi_bready),
    .s_axi_arready(axi_arready),
    .s_axi_rvalid(axi_rvalid),
    .s_axi_awready(axi_awready),
    .s_axi_wready(axi_wready),
    .s_axi_bvalid(axi_bvalid),
    .s_axi_rdata(axi_rdata),
    .s_axi_rresp(axi_rresp),
    .s_axi_bresp(axi_bresp));
  ibex_jtag_axi u_jtag (.aclk(clk_i), .aresetn(axi_resetn),
    .m_axi_araddr(axi_araddr),
    .m_axi_awaddr(axi_awaddr),
    .m_axi_wdata(axi_wdata),
    .m_axi_arprot(axi_arprot),
    .m_axi_awprot(axi_awprot),
    .m_axi_wstrb(axi_wstrb),
    .m_axi_arvalid(axi_arvalid),
    .m_axi_rready(axi_rready),
    .m_axi_awvalid(axi_awvalid),
    .m_axi_wvalid(axi_wvalid),
    .m_axi_bready(axi_bready),
    .m_axi_arready(axi_arready),
    .m_axi_rvalid(axi_rvalid),
    .m_axi_awready(axi_awready),
    .m_axi_wready(axi_wready),
    .m_axi_bvalid(axi_bvalid),
    .m_axi_rdata(axi_rdata),
    .m_axi_rresp(axi_rresp),
    .m_axi_bresp(axi_bresp));
  ibex_reset_vio u_vio (.clk(clk_i), .probe_in0({major_bus,major_int,minor,sleep}), .probe_out0(reset_cpu));
endmodule

