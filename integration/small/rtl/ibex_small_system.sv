// SPDX-License-Identifier: Apache-2.0
module ibex_small_system #(parameter RomFile="", parameter RamPrimitive="block", parameter ProgramPrimitive="block", parameter int unsigned BootImageWords=65536, parameter bit EnableInputMailbox=1'b0, parameter bit EnableFirmwareLoader=1'b0, parameter bit EnablePeripherals=1'b0, parameter bit EnableIspAccess=1'b0, parameter bit EnableIspConfig=1'b0, parameter bit EnableCpuResetInput=1'b0, parameter bit EnableSensorControl=1'b0) (
 input wire cpu_rst_ni,
 input wire sensor_owner_i,sensor_run_i,sensor_stop_i,
 input wire sensor_ps_scl_release_i,sensor_ps_sda_release_i,sensor_scl_i,sensor_sda_i,
 output wire sensor_scl_low_o,sensor_sda_low_o,sensor_grant_o,
 output wire [31:0] sensor_status_o,
 input wire isp_cfg_clk_i,isp_cfg_rst_ni,
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
 input logic clk_i, rst_ni,
 input logic video_clk_i, video_rst_ni,
 input logic [511:0] isp_stats_i,
 input logic [15:0] isp_fe_seq_i,
 input logic [13:0] isp_sof_seq_i,
 input logic irq_software_i, irq_timer_i, irq_external_i,
 input logic [14:0] irq_fast_i,
 input logic irq_nm_i, debug_req_i,
 input logic [31:0] s_axi_araddr, s_axi_awaddr, s_axi_wdata,
  input logic [2:0] s_axi_arprot, s_axi_awprot,
  input logic [3:0] s_axi_wstrb,
  input logic s_axi_arvalid, s_axi_rready, s_axi_awvalid, s_axi_wvalid, s_axi_bready,
  output logic s_axi_arready, s_axi_rvalid, s_axi_awready, s_axi_wready, s_axi_bvalid,
  output logic [31:0] s_axi_rdata,
  output logic [1:0] s_axi_rresp, s_axi_bresp,
 input logic [31:0] loader_axi_araddr, loader_axi_awaddr, loader_axi_wdata,
  input logic [2:0] loader_axi_arprot, loader_axi_awprot,
  input logic [3:0] loader_axi_wstrb,
  input logic loader_axi_arvalid, loader_axi_rready, loader_axi_awvalid, loader_axi_wvalid, loader_axi_bready,
  output logic loader_axi_arready, loader_axi_rvalid, loader_axi_awready, loader_axi_wready, loader_axi_bvalid,
  output logic [31:0] loader_axi_rdata,
  output logic [1:0] loader_axi_rresp, loader_axi_bresp,
 input logic [31:0] gpio_i,
 output logic [31:0] gpio_o, gpio_oe_o,
 input logic i2c_scl_i, i2c_sda_i,
 output logic i2c_scl_o, i2c_scl_oe_o, i2c_sda_o, i2c_sda_oe_o,
 input logic uart_rx_i,
 output logic uart_tx_o,
 output logic peripheral_alert_o,
 output logic core_sleep_o, alert_minor_o, alert_major_internal_o, alert_major_bus_o
);
logic cpu_reset_n;
logic memory_ready;
logic loader_cpu_reset_n;
logic load_req, load_we;
logic [31:0] load_addr, load_wdata, load_rdata;
logic [3:0] load_be;
logic instr_req;
logic instr_gnt;
logic instr_rvalid;
logic [31:0] instr_addr;
logic [31:0] instr_rdata;
logic instr_err;
logic data_req;
logic data_gnt;
logic data_rvalid;
logic data_we;
logic [3:0] data_be;
logic [31:0] data_addr;
logic [31:0] data_wdata;
logic [31:0] data_rdata;
logic data_err;
logic bus_req, bus_gnt, bus_rvalid, bus_err;
logic local_req,local_gnt,local_valid,local_error;
logic [31:0] local_data;
logic [31:0] bus_rdata;
logic mem_req, mem_gnt, mem_rvalid, mem_err;
logic [31:0] mem_rdata;
logic isp_event_irq;
logic peripheral_timer_irq, peripheral_external_irq, peripheral_uart_irq;
ibex_small_core u_core (
.clk_i(clk_i),
.rst_ni(cpu_reset_n),
.irq_software_i(irq_software_i),
.irq_timer_i(irq_timer_i | peripheral_timer_irq),
.irq_external_i(irq_external_i | peripheral_external_irq),
.irq_fast_i({irq_fast_i[14:2], EnableIspAccess ? isp_event_irq : irq_fast_i[1], EnablePeripherals ? peripheral_uart_irq : irq_fast_i[0]}),
.irq_nm_i(irq_nm_i),
.debug_req_i(debug_req_i),
.core_sleep_o(core_sleep_o),
.alert_minor_o(alert_minor_o),
.alert_major_internal_o(alert_major_internal_o),
.alert_major_bus_o(alert_major_bus_o),
.hart_id_i(32'b0),
.boot_addr_i(32'h00100000),
.instr_req_o(instr_req),
.instr_gnt_i(instr_gnt),
.instr_rvalid_i(instr_rvalid),
.instr_addr_o(instr_addr),
.instr_rdata_i(instr_rdata),
.instr_err_i(instr_err),
.data_req_o(data_req),
.data_gnt_i(data_gnt),
.data_rvalid_i(data_rvalid),
.data_we_o(data_we),
.data_be_o(data_be),
.data_addr_o(data_addr),
.data_wdata_o(data_wdata),
.data_rdata_i(data_rdata),
.data_err_i(data_err));
ibex_small_mem #(.RomFile(RomFile), .RamPrimitive(RamPrimitive), .ProgramPrimitive(ProgramPrimitive), .BootImageWords(BootImageWords), .EnableInputMailbox(EnableInputMailbox), .EnableFirmwareLoader(EnableFirmwareLoader)) u_mem (
.clk_i(clk_i), .rst_ni(rst_ni),
.cpu_rst_ni(cpu_reset_n), .memory_ready_o(memory_ready),
.load_req_i(load_req), .load_we_i(load_we),
.load_addr_i(load_addr), .load_wdata_i(load_wdata),
.load_be_i(load_be), .load_rdata_o(load_rdata),
.instr_req_i(instr_req),
.instr_gnt_o(instr_gnt),
.instr_rvalid_o(instr_rvalid),
.instr_addr_i(instr_addr),
.instr_rdata_o(instr_rdata),
.instr_err_o(instr_err),
.data_req_i(mem_req),
.data_gnt_o(mem_gnt),
.data_rvalid_o(mem_rvalid),
.data_we_i(data_we),
.data_be_i(data_be),
.data_addr_i(data_addr),
.data_wdata_i(data_wdata),
.data_rdata_o(mem_rdata),
.data_err_o(mem_err),
.s_axi_araddr(s_axi_araddr),
.s_axi_awaddr(s_axi_awaddr),
.s_axi_wdata(s_axi_wdata),
.s_axi_arprot(s_axi_arprot),
.s_axi_awprot(s_axi_awprot),
.s_axi_wstrb(s_axi_wstrb),
.s_axi_arvalid(s_axi_arvalid),
.s_axi_rready(s_axi_rready),
.s_axi_awvalid(s_axi_awvalid),
.s_axi_wvalid(s_axi_wvalid),
.s_axi_bready(s_axi_bready),
.s_axi_arready(s_axi_arready),
.s_axi_rvalid(s_axi_rvalid),
.s_axi_awready(s_axi_awready),
.s_axi_wready(s_axi_wready),
.s_axi_bvalid(s_axi_bvalid),
.s_axi_rdata(s_axi_rdata),
.s_axi_rresp(s_axi_rresp),
.s_axi_bresp(s_axi_bresp));
generate
 if(EnableIspAccess || EnableIspConfig || EnableSensorControl) begin: gen_isp
  logic pending_q;
  logic [1:0] selected_q;
  logic isp_gnt,isp_valid,isp_err,cfg_gnt,cfg_valid,cfg_err;
  logic [31:0] isp_data,cfg_data;
  wire snapshot_selected=EnableIspAccess && data_addr[31:7]==25'h0a00000;
  wire config_selected=EnableIspConfig && data_addr[31:16]==16'h5100;
  wire sensor_selected=EnableSensorControl && data_addr[31:8]==24'h520000;
  wire [1:0] selected=sensor_selected ? 2'd3 : config_selected ? 2'd2 : snapshot_selected ? 2'd1 : 2'd0;
  assign local_req=data_req && !pending_q && sensor_selected;
  assign bus_req=data_req && !pending_q && selected==0;
  assign data_gnt=!pending_q && (selected==3 ? local_gnt : selected==2 ? cfg_gnt : selected==1 ? isp_gnt : bus_gnt);
  assign data_rvalid=pending_q && (selected_q==3 ? local_valid : selected_q==2 ? cfg_valid : selected_q==1 ? isp_valid : bus_rvalid);
  assign data_rdata=selected_q==3 ? local_data : selected_q==2 ? cfg_data : selected_q==1 ? isp_data : bus_rdata;
  assign data_err=selected_q==3 ? local_error : selected_q==2 ? cfg_err : selected_q==1 ? isp_err : bus_err;
  always_ff @(posedge clk_i or negedge cpu_reset_n)
   if(!cpu_reset_n) begin pending_q<=0;selected_q<=0;end
   else if(data_rvalid) pending_q<=0;
   else if(data_req&&data_gnt) begin pending_q<=1;selected_q<=selected;end
  if(EnableIspAccess) begin: gen_snapshot
   ibex_isp_snapshot u_snapshot(
    .clk_i,.rst_ni(cpu_reset_n),.video_clk_i,.video_rst_ni,
    .stats_i(isp_stats_i),.fe_seq_i(isp_fe_seq_i),.sof_seq_i(isp_sof_seq_i),
    .req_i(data_req && !pending_q && snapshot_selected),.we_i(data_we),.addr_i(data_addr),.wdata_i(data_wdata),
    .gnt_o(isp_gnt),.rvalid_o(isp_valid),.rdata_o(isp_data),.err_o(isp_err),.irq_o(isp_event_irq));
  end else begin: gen_no_snapshot
   assign isp_gnt=0;assign isp_valid=0;assign isp_data=0;assign isp_err=0;assign isp_event_irq=0;
  end
  if(EnableIspConfig) begin: gen_config
   logic cfg_req,cfg_we,cfg_target_gnt,cfg_target_valid,cfg_target_err;
   logic [31:0] cfg_addr,cfg_wdata,cfg_rdata;
   logic [3:0] cfg_be;
   ibex_isp_cfg_cdc u_cdc (
    .clk_i,.rst_ni,.cfg_clk_i(isp_cfg_clk_i),.cfg_rst_ni(isp_cfg_rst_ni),
    .req_i(data_req && !pending_q && config_selected),.we_i(data_we),
    .addr_i(data_addr),.wdata_i(data_wdata),.be_i(data_be),
    .gnt_o(cfg_gnt),.rvalid_o(cfg_valid),.rdata_o(cfg_data),.err_o(cfg_err),
    .req_o(cfg_req),.we_o(cfg_we),.addr_o(cfg_addr),.wdata_o(cfg_wdata),.be_o(cfg_be),
    .gnt_i(cfg_target_gnt),.rvalid_i(cfg_target_valid),.rdata_i(cfg_rdata),.err_i(cfg_target_err));
   ibex_native_to_axi_lite u_master (
    .clk_i(isp_cfg_clk_i),.rst_ni(isp_cfg_rst_ni && rst_ni),
    .req_i(cfg_req),.we_i(cfg_we),.addr_i(cfg_addr),.wdata_i(cfg_wdata),.be_i(cfg_be),
    .gnt_o(cfg_target_gnt),.rvalid_o(cfg_target_valid),.rdata_o(cfg_rdata),.err_o(cfg_target_err),
    .m_axi_awaddr(m_isp_axi_awaddr),
    .m_axi_awvalid(m_isp_axi_awvalid),
    .m_axi_awready(m_isp_axi_awready),
    .m_axi_wdata(m_isp_axi_wdata),
    .m_axi_wstrb(m_isp_axi_wstrb),
    .m_axi_wvalid(m_isp_axi_wvalid),
    .m_axi_wready(m_isp_axi_wready),
    .m_axi_bresp(m_isp_axi_bresp),
    .m_axi_bvalid(m_isp_axi_bvalid),
    .m_axi_bready(m_isp_axi_bready),
    .m_axi_araddr(m_isp_axi_araddr),
    .m_axi_arvalid(m_isp_axi_arvalid),
    .m_axi_arready(m_isp_axi_arready),
    .m_axi_rdata(m_isp_axi_rdata),
    .m_axi_rresp(m_isp_axi_rresp),
    .m_axi_rvalid(m_isp_axi_rvalid),
    .m_axi_rready(m_isp_axi_rready));
  end else begin: gen_no_config
   assign cfg_gnt=0;assign cfg_valid=0;assign cfg_data=0;assign cfg_err=0;
   assign m_isp_axi_awaddr=0;
   assign m_isp_axi_awvalid=0;
   assign m_isp_axi_wdata=0;
   assign m_isp_axi_wstrb=0;
   assign m_isp_axi_wvalid=0;
   assign m_isp_axi_bready=0;
   assign m_isp_axi_araddr=0;
   assign m_isp_axi_arvalid=0;
   assign m_isp_axi_rready=0;
  end
 end else begin: gen_no_isp
  assign local_req=1'b0;
  assign isp_event_irq=1'b0;
  assign bus_req=data_req;assign data_gnt=bus_gnt;
  assign data_rvalid=bus_rvalid;assign data_rdata=bus_rdata;assign data_err=bus_err;
  assign m_isp_axi_awaddr=0;
  assign m_isp_axi_awvalid=0;
  assign m_isp_axi_wdata=0;
  assign m_isp_axi_wstrb=0;
  assign m_isp_axi_wvalid=0;
  assign m_isp_axi_bready=0;
  assign m_isp_axi_araddr=0;
  assign m_isp_axi_arvalid=0;
  assign m_isp_axi_rready=0;
 end
endgenerate
generate
 if(EnableSensorControl) begin: gen_sensor
  ibex_sensor_ctrl u_sensor (
   .clk_i,.rst_ni,.cpu_rst_ni(cpu_reset_n),
   .owner_async_i(sensor_owner_i),.run_async_i(sensor_run_i),.stop_async_i(sensor_stop_i),
   .ps_scl_release_i(sensor_ps_scl_release_i),.ps_sda_release_i(sensor_ps_sda_release_i),
   .scl_i(sensor_scl_i),.sda_i(sensor_sda_i),
   .req_i(local_req),.we_i(data_we),.addr_i(data_addr),.wdata_i(data_wdata),.be_i(data_be),
   .gnt_o(local_gnt),.rvalid_o(local_valid),.err_o(local_error),.rdata_o(local_data),
   .scl_low_o(sensor_scl_low_o),.sda_low_o(sensor_sda_low_o),.grant_o(sensor_grant_o),.status_o(sensor_status_o));
 end else begin: gen_no_sensor
  assign local_gnt=0;assign local_valid=0;assign local_error=0;assign local_data=0;
  assign sensor_scl_low_o=0;assign sensor_sda_low_o=0;assign sensor_grant_o=0;assign sensor_status_o=0;
 end
endgenerate
generate
  if (EnablePeripherals) begin : gen_peripherals
    logic peripheral_req, peripheral_gnt, peripheral_rvalid, peripheral_err;
    logic [31:0] peripheral_rdata;
    logic peripheral_select, pending_q, response_peripheral_q;
    logic peripheral_alert, integrity_error;
    // Serialize the two destinations so a slow TL-UL response cannot reorder
    // against the single-cycle memory response. Selection is saved on acceptance.
    assign peripheral_select = data_addr[31:18] == 14'h1000;
    assign mem_req = bus_req && !pending_q && !peripheral_select;
    assign peripheral_req = bus_req && !pending_q && peripheral_select;
    assign bus_gnt = !pending_q &&
                      (peripheral_select ? peripheral_gnt : mem_gnt);
    assign bus_rvalid = pending_q &&
                        (response_peripheral_q ? peripheral_rvalid : mem_rvalid);
    assign bus_rdata = response_peripheral_q ? peripheral_rdata : mem_rdata;
    assign bus_err = response_peripheral_q ? peripheral_err : mem_err;
    always_ff @(posedge clk_i or negedge cpu_reset_n) begin
      if (!cpu_reset_n) begin
        pending_q <= 1'b0;
        response_peripheral_q <= 1'b0;
      end else if (bus_rvalid) begin
        pending_q <= 1'b0;
      end else if (bus_req && bus_gnt) begin
        pending_q <= 1'b1;
        response_peripheral_q <= peripheral_select;
      end
    end
    assign peripheral_alert_o = peripheral_alert | integrity_error;
    ibex_opentitan_peripherals u_peripherals (
      .clk_i, .rst_ni(cpu_reset_n), .req_i(peripheral_req), .we_i(data_we),
      .addr_i(data_addr), .wdata_i(data_wdata), .be_i(data_be),
      .gnt_o(peripheral_gnt), .rvalid_o(peripheral_rvalid),
      .rdata_o(peripheral_rdata), .err_o(peripheral_err),
      .integrity_error_o(integrity_error), .alert_o(peripheral_alert),
      .irq_timer_o(peripheral_timer_irq), .irq_external_o(peripheral_external_irq),
      .irq_uart_o(peripheral_uart_irq),
      .gpio_i, .gpio_o, .gpio_oe_o, .i2c_scl_i, .i2c_sda_i,
      .i2c_scl_o, .i2c_scl_oe_o, .i2c_sda_o, .i2c_sda_oe_o,
      .uart_rx_i, .uart_tx_o
    );
  end else begin : gen_no_peripherals
    assign mem_req = bus_req;
    assign bus_gnt = mem_gnt;
    assign bus_rvalid = mem_rvalid;
    assign bus_rdata = mem_rdata;
    assign bus_err = mem_err;
    assign peripheral_timer_irq = 1'b0;
    assign peripheral_external_irq = 1'b0;
    assign peripheral_uart_irq = 1'b0;
    assign peripheral_alert_o = 1'b0;
    assign gpio_o = '0;
    assign gpio_oe_o = '0;
    assign i2c_scl_o = 1'b0;
    assign i2c_sda_o = 1'b0;
    assign i2c_scl_oe_o = 1'b0;
    assign i2c_sda_oe_o = 1'b0;
    assign uart_tx_o = 1'b1;
  end
  if (EnableFirmwareLoader) begin : gen_loader
    assign cpu_reset_n=memory_ready && loader_cpu_reset_n && (!EnableCpuResetInput || cpu_rst_ni);
    ibex_small_loader u_loader (
      .clk_i(clk_i), .rst_ni(rst_ni && memory_ready), .cpu_rst_no(loader_cpu_reset_n),
      .load_req_o(load_req), .load_we_o(load_we),
      .load_addr_o(load_addr), .load_wdata_o(load_wdata),
      .load_be_o(load_be), .load_rdata_i(load_rdata),
      .s_axi_araddr(loader_axi_araddr),
      .s_axi_awaddr(loader_axi_awaddr),
      .s_axi_wdata(loader_axi_wdata),
      .s_axi_arprot(loader_axi_arprot),
      .s_axi_awprot(loader_axi_awprot),
      .s_axi_wstrb(loader_axi_wstrb),
      .s_axi_arvalid(loader_axi_arvalid),
      .s_axi_rready(loader_axi_rready),
      .s_axi_awvalid(loader_axi_awvalid),
      .s_axi_wvalid(loader_axi_wvalid),
      .s_axi_bready(loader_axi_bready),
      .s_axi_arready(loader_axi_arready),
      .s_axi_rvalid(loader_axi_rvalid),
      .s_axi_awready(loader_axi_awready),
      .s_axi_wready(loader_axi_wready),
      .s_axi_bvalid(loader_axi_bvalid),
      .s_axi_rdata(loader_axi_rdata),
      .s_axi_rresp(loader_axi_rresp),
      .s_axi_bresp(loader_axi_bresp)
    );
  end else begin : gen_legacy
    assign cpu_reset_n = rst_ni && memory_ready && (!EnableCpuResetInput || cpu_rst_ni);
    assign load_req = 1'b0;
    assign load_we = 1'b0;
    assign load_addr = 32'b0;
    assign load_wdata = 32'b0;
    assign load_be = 4'b0;
    assign loader_axi_arready = '0;
    assign loader_axi_rvalid = '0;
    assign loader_axi_awready = '0;
    assign loader_axi_wready = '0;
    assign loader_axi_bvalid = '0;
    assign loader_axi_rdata = '0;
    assign loader_axi_rresp = '0;
    assign loader_axi_bresp = '0;
  end
endgenerate
endmodule
