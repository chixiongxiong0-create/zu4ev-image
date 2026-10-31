`timescale 1ns/1ps
module tb_isp_config_cpu;
reg clk=0, vc=0, rst=0, cr=0, cpu_rst=1, hold_aw=1; wire regs_awready; always #5 clk=~clk; always #7 vc=~vc;
reg [15:0] ps_awaddr=0,ps_araddr=0; reg [31:0] ps_wdata=0; reg [3:0] ps_wstrb=0;
reg ps_awvalid=0,ps_wvalid=0,ps_bready=0,ps_arvalid=0,ps_rready=0;
wire [15:0] cpu_awaddr;
wire cpu_awvalid;
wire cpu_awready;
wire [31:0] cpu_wdata;
wire [3:0] cpu_wstrb;
wire cpu_wvalid;
wire cpu_wready;
wire [1:0] cpu_bresp;
wire cpu_bvalid;
wire cpu_bready;
wire [15:0] cpu_araddr;
wire cpu_arvalid;
wire cpu_arready;
wire [31:0] cpu_rdata;
wire [1:0] cpu_rresp;
wire cpu_rvalid;
wire cpu_rready;
wire [15:0] m_awaddr;
wire m_awvalid;
wire m_awready; assign m_awready=regs_awready && !hold_aw;
wire [31:0] m_wdata;
wire [3:0] m_wstrb;
wire m_wvalid;
wire m_wready;
wire [1:0] m_bresp;
wire m_bvalid;
wire m_bready;
wire [15:0] m_araddr;
wire m_arvalid;
wire m_arready;
wire [31:0] m_rdata;
wire [1:0] m_rresp;
wire m_rvalid;
wire m_rready;
wire ps_awready;
wire ps_wready;
wire [1:0] ps_bresp;
wire ps_bvalid;
wire ps_arready;
wire [31:0] ps_rdata;
wire [1:0] ps_rresp;
wire ps_rvalid;
wire [1:0] cfg_mode; wire [9:0] ae_black; wire cfg_pending;
ibex_small_system #(.RomFile("isp_config_cpu.mem"),.EnableIspAccess(1),.EnableIspConfig(1),.EnableCpuResetInput(1)) dut(
 .cpu_rst_ni(cpu_rst),.clk_i(clk),.rst_ni(cr),.video_clk_i(vc),.video_rst_ni(rst),.isp_cfg_clk_i(vc),.isp_cfg_rst_ni(rst),
 .isp_stats_i({480'b0,32'h12345678}),.isp_fe_seq_i(16'b0),.isp_sof_seq_i(14'b0),
 .irq_software_i(1'b0),.irq_timer_i(1'b0),.irq_external_i(1'b0),.irq_fast_i('0),.irq_nm_i(1'b0),.debug_req_i(1'b0),
 .s_axi_araddr('0),.s_axi_awaddr('0),.s_axi_wdata('0),.s_axi_arprot('0),.s_axi_awprot('0),.s_axi_wstrb('0),.s_axi_arvalid(1'b0),.s_axi_rready(1'b0),.s_axi_awvalid(1'b0),.s_axi_wvalid(1'b0),.s_axi_bready(1'b0),
 .loader_axi_araddr('0),.loader_axi_awaddr('0),.loader_axi_wdata('0),.loader_axi_arprot('0),.loader_axi_awprot('0),.loader_axi_wstrb('0),.loader_axi_arvalid(1'b0),.loader_axi_rready(1'b0),.loader_axi_awvalid(1'b0),.loader_axi_wvalid(1'b0),.loader_axi_bready(1'b0),
 .gpio_i('0),.i2c_scl_i(1'b1),.i2c_sda_i(1'b1),.uart_rx_i(1'b1),
 .m_isp_axi_awaddr(cpu_awaddr),
 .m_isp_axi_awvalid(cpu_awvalid),
 .m_isp_axi_awready(cpu_awready),
 .m_isp_axi_wdata(cpu_wdata),
 .m_isp_axi_wstrb(cpu_wstrb),
 .m_isp_axi_wvalid(cpu_wvalid),
 .m_isp_axi_wready(cpu_wready),
 .m_isp_axi_bresp(cpu_bresp),
 .m_isp_axi_bvalid(cpu_bvalid),
 .m_isp_axi_bready(cpu_bready),
 .m_isp_axi_araddr(cpu_araddr),
 .m_isp_axi_arvalid(cpu_arvalid),
 .m_isp_axi_arready(cpu_arready),
 .m_isp_axi_rdata(cpu_rdata),
 .m_isp_axi_rresp(cpu_rresp),
 .m_isp_axi_rvalid(cpu_rvalid),
 .m_isp_axi_rready(cpu_rready));
ibex_isp_cfg_owner owner(.clk_i(vc),.rst_ni(rst),
 .ps_axi_awaddr(ps_awaddr),
 .ps_axi_awvalid(ps_awvalid),
 .ps_axi_awready(ps_awready),
 .ps_axi_wdata(ps_wdata),
 .ps_axi_wstrb(ps_wstrb),
 .ps_axi_wvalid(ps_wvalid),
 .ps_axi_wready(ps_wready),
 .ps_axi_bresp(ps_bresp),
 .ps_axi_bvalid(ps_bvalid),
 .ps_axi_bready(ps_bready),
 .ps_axi_araddr(ps_araddr),
 .ps_axi_arvalid(ps_arvalid),
 .ps_axi_arready(ps_arready),
 .ps_axi_rdata(ps_rdata),
 .ps_axi_rresp(ps_rresp),
 .ps_axi_rvalid(ps_rvalid),
 .ps_axi_rready(ps_rready),
 .cpu_axi_awaddr(cpu_awaddr),
 .cpu_axi_awvalid(cpu_awvalid),
 .cpu_axi_awready(cpu_awready),
 .cpu_axi_wdata(cpu_wdata),
 .cpu_axi_wstrb(cpu_wstrb),
 .cpu_axi_wvalid(cpu_wvalid),
 .cpu_axi_wready(cpu_wready),
 .cpu_axi_bresp(cpu_bresp),
 .cpu_axi_bvalid(cpu_bvalid),
 .cpu_axi_bready(cpu_bready),
 .cpu_axi_araddr(cpu_araddr),
 .cpu_axi_arvalid(cpu_arvalid),
 .cpu_axi_arready(cpu_arready),
 .cpu_axi_rdata(cpu_rdata),
 .cpu_axi_rresp(cpu_rresp),
 .cpu_axi_rvalid(cpu_rvalid),
 .cpu_axi_rready(cpu_rready),
 .m_axi_awaddr(m_awaddr),
 .m_axi_awvalid(m_awvalid),
 .m_axi_awready(m_awready),
 .m_axi_wdata(m_wdata),
 .m_axi_wstrb(m_wstrb),
 .m_axi_wvalid(m_wvalid),
 .m_axi_wready(m_wready),
 .m_axi_bresp(m_bresp),
 .m_axi_bvalid(m_bvalid),
 .m_axi_bready(m_bready),
 .m_axi_araddr(m_araddr),
 .m_axi_arvalid(m_arvalid),
 .m_axi_arready(m_arready),
 .m_axi_rdata(m_rdata),
 .m_axi_rresp(m_rresp),
 .m_axi_rvalid(m_rvalid),
 .m_axi_rready(m_rready));
isp_axi_regs #(.AE_STATS(1)) regs(.clk(vc),.resetn(rst),
 .s_axi_awaddr(m_awaddr),
 .s_axi_awvalid(m_awvalid && !hold_aw),
 .s_axi_awready(regs_awready),
 .s_axi_wdata(m_wdata),
 .s_axi_wstrb(m_wstrb),
 .s_axi_wvalid(m_wvalid),
 .s_axi_wready(m_wready),
 .s_axi_bresp(m_bresp),
 .s_axi_bvalid(m_bvalid),
 .s_axi_bready(m_bready),
 .s_axi_araddr(m_araddr),
 .s_axi_arvalid(m_arvalid),
 .s_axi_arready(m_arready),
 .s_axi_rdata(m_rdata),
 .s_axi_rresp(m_rresp),
 .s_axi_rvalid(m_rvalid),
 .s_axi_rready(m_rready),
 .cfg_safe(1'b1),.frame_busy(1'b0),.frame_done(1'b0),.fault_count(32'b0),.fifo_level(13'b0),
 .cfg_pending(cfg_pending),.cfg_mode(cfg_mode),.ae_black(ae_black),.curve_rdata(10'b0),
 .ae_valid(1'b0),.ae_busy(1'b0),.ae_active(1'b0),.ae_seq(32'b0),.ae_frame(32'b0),.ae_mean(32'b0),.ae_count(32'b0),.ae_bad(32'b0),.ae_overrun(32'b0),.ae_sum(48'b0),.ae_result_region(2'b0),.ae_result_black(10'b0),.ae_x(32'b0),.ae_y(32'b0),.ae_width(32'b0),.ae_height(32'b0));
reg [31:0] got[0:3]; integer n; integer forwarded_writes=0;
always @(posedge vc) if(m_wvalid && m_wready) forwarded_writes<=forwarded_writes+1;
always @(negedge clk) if(dut.data_gnt && dut.data_we && dut.data_addr>=32'h200000 && dut.data_addr<=32'h20000c) got[(dut.data_addr-32'h200000)/4]=dut.data_wdata;
always @(negedge clk) if(dut.data_gnt && dut.data_we && dut.data_addr==32'h200010) begin
 if(got[0]!==32'h49535031 || got[1]!==2 || got[2]!==32'h57 || got[3]!==32'h12345678 || cfg_mode!==2 || ae_black!==10'h57 || forwarded_writes!==4) $fatal(1,"bad results %h %h %h %h mode=%h ae=%h writes=%d",got[0],got[1],got[2],got[3],cfg_mode,ae_black,forwarded_writes);
 $display("PASS asynchronous real Ibex ISP config and snapshot"); $finish; end
initial begin
 repeat(4) @(negedge vc);rst=1;
 // PS grants CPU before it reaches configuration requests.
 @(negedge vc);ps_awaddr=16'hff00;ps_awvalid=1;ps_wdata=1;ps_wstrb=15;ps_wvalid=1;ps_bready=1;
 fork begin do @(posedge vc); while(!ps_awready); @(negedge vc);ps_awvalid=0; end
      begin do @(posedge vc); while(!ps_wready); @(negedge vc);ps_wvalid=0; end join
 do @(posedge vc); while(!ps_bvalid); if(ps_bresp!==0) $fatal(1,"ownership grant failed");
 @(negedge vc);ps_bready=0; cr=1;
end
initial begin
 wait(m_wvalid && m_wready); cpu_rst=0; repeat(8) @(negedge vc); hold_aw=0;
 wait(m_bvalid && m_bready); repeat(8) @(negedge clk); cpu_rst=1;
end
initial begin #500000;$fatal(1,"timeout pc=%h",dut.instr_addr);end
endmodule






