`timescale 1ns/1ps
// Capture-facing ISP wrapper. Legacy callers preserve the old one-cycle path;
// the live top explicitly selects buffered LTM and its conservative fault path.
module isp_capture_frontend #(
 parameter integer USE_LTM=0,WIDTH=1280,HEIGHT=1024,RUNTIME_CONFIG=0
)(
 output wire [511:0] ibex_stats_o, input wire ibex_cfg_reset_ni,
 input wire [15:0] isp_axi_awaddr,
 input wire isp_axi_awvalid,
 output wire isp_axi_awready,
 input wire [31:0] isp_axi_wdata,
 input wire [3:0] isp_axi_wstrb,
 input wire isp_axi_wvalid,
 output wire isp_axi_wready,
 output wire [1:0] isp_axi_bresp,
 output wire isp_axi_bvalid,
 input wire isp_axi_bready,
 input wire [15:0] isp_axi_araddr,
 input wire isp_axi_arvalid,
 output wire isp_axi_arready,
 output wire [31:0] isp_axi_rdata,
 output wire [1:0] isp_axi_rresp,
 output wire isp_axi_rvalid,
 input wire isp_axi_rready,
 input wire clk,resetn,input wire [19:0] s_data,
 input wire s_valid,s_sof,s_eol,s_packet_error,s_global_fault,
 output wire [31:0] m_data,output wire m_valid,m_sof,m_eol,
 output wire m_packet_error,m_global_fault,m_fault,
 output wire [31:0] fault_count,output wire [12:0] fifo_level);
 wire cfg_pending,cfg_safe,frame_busy,frame_done,cfg_bank,curve_we,curve_re,cfg_tone_enable;
 wire [1:0] cfg_mode,cfg_range;
 wire [9:0] cfg_black,cfg_gain,curve_waddr,curve_wdata,curve_raddr,curve_rdata;
 generate if(USE_LTM&&RUNTIME_CONFIG)begin: control
  wire ae_enable,ae_valid,ae_busy,ae_active;
  wire [1:0] ae_region,ae_result_region;wire [9:0] ae_black,ae_result_black;
  wire [31:0] ae_seq,ae_frame,ae_mean,ae_count,ae_bad,ae_overrun,ae_x,ae_y,ae_width,ae_height;
  wire [47:0] ae_sum;
  assign ibex_stats_o={ae_height,ae_width,ae_y,ae_x,ae_overrun,ae_bad,{20'b0,ae_result_black,ae_result_region},{29'b0,ae_active,ae_busy,ae_valid},16'b0,ae_sum,ae_count,ae_mean,ae_frame,ae_seq,64'b0};
  ae_stats_raw10 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) statistics(
   .clk(clk),.resetn(resetn),.s_data(s_data),.s_valid(s_valid),.s_sof(s_sof),.s_eol(s_eol),
   .s_packet_error(s_packet_error),.s_global_fault(s_global_fault),
   .cfg_enable(ae_enable),.cfg_region(ae_region),.cfg_black(ae_black),
   .result_valid(ae_valid),.div_busy(ae_busy),.active_enable(ae_active),
   .result_seq(ae_seq),.result_frame(ae_frame),.result_mean(ae_mean),.result_count(ae_count),
   .result_sum(ae_sum),.bad_frames(ae_bad),.overruns(ae_overrun),
   .result_region(ae_result_region),.result_black(ae_result_black),
   .roi_x(ae_x),.roi_y(ae_y),.roi_width(ae_width),.roi_height(ae_height));
  isp_axi_regs #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.AE_STATS(1)) registers(
   .ae_enable(ae_enable),.ae_region(ae_region),.ae_black(ae_black),
   .ae_valid(ae_valid),.ae_busy(ae_busy),.ae_active(ae_active),
   .ae_seq(ae_seq),.ae_frame(ae_frame),.ae_mean(ae_mean),.ae_count(ae_count),
   .ae_sum(ae_sum),.ae_bad(ae_bad),.ae_overrun(ae_overrun),
   .ae_result_region(ae_result_region),.ae_result_black(ae_result_black),
   .ae_x(ae_x),.ae_y(ae_y),.ae_width(ae_width),.ae_height(ae_height),
   .clk(clk),.resetn(ibex_cfg_reset_ni),.s_axi_awaddr(isp_axi_awaddr),
   .s_axi_awvalid(isp_axi_awvalid),
   .s_axi_awready(isp_axi_awready),
   .s_axi_wdata(isp_axi_wdata),
   .s_axi_wstrb(isp_axi_wstrb),
   .s_axi_wvalid(isp_axi_wvalid),
   .s_axi_wready(isp_axi_wready),
   .s_axi_bresp(isp_axi_bresp),
   .s_axi_bvalid(isp_axi_bvalid),
   .s_axi_bready(isp_axi_bready),
   .s_axi_araddr(isp_axi_araddr),
   .s_axi_arvalid(isp_axi_arvalid),
   .s_axi_arready(isp_axi_arready),
   .s_axi_rdata(isp_axi_rdata),
   .s_axi_rresp(isp_axi_rresp),
   .s_axi_rvalid(isp_axi_rvalid),
   .s_axi_rready(isp_axi_rready),
   .cfg_safe(cfg_safe),.frame_busy(frame_busy),.frame_done(frame_done),
   .fault_count(fault_count),.fifo_level(fifo_level),
   .cfg_pending(cfg_pending),.cfg_mode(cfg_mode),.cfg_black(cfg_black),.cfg_gain(cfg_gain),
   .cfg_range(cfg_range),.cfg_bank(cfg_bank),.cfg_tone_enable(cfg_tone_enable),.curve_we(curve_we),.curve_waddr(curve_waddr),
   .curve_wdata(curve_wdata),.curve_re(curve_re),.curve_raddr(curve_raddr),.curve_rdata(curve_rdata));
 end else begin: no_control
  assign ibex_stats_o=512'b0;
  assign {cfg_pending,cfg_mode,cfg_range,cfg_bank,curve_we,curve_re}=0;
  assign cfg_black=52;assign cfg_gain=256;
  assign cfg_tone_enable=1;
  assign curve_waddr=0;assign curve_wdata=0;assign curve_raddr=0;
  assign isp_axi_awready=0;assign isp_axi_wready=0;assign isp_axi_bresp=2;assign isp_axi_bvalid=0;
  assign isp_axi_arready=0;assign isp_axi_rdata=0;assign isp_axi_rresp=2;assign isp_axi_rvalid=0;
 end endgenerate
 generate if(USE_LTM)begin: local_tone
  ltm_camera_ingress #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.RUNTIME_CONFIG(RUNTIME_CONFIG)) ingress(
   .cfg_pending(cfg_pending),.cfg_safe(cfg_safe),.frame_busy(frame_busy),.frame_done(frame_done),
   .cfg_mode(cfg_mode),.cfg_black(cfg_black),.cfg_gain(cfg_gain),.cfg_range(cfg_range),.cfg_bank(cfg_bank),.cfg_tone_enable(cfg_tone_enable),
   .curve_we(curve_we),.curve_waddr(curve_waddr),.curve_wdata(curve_wdata),
   .curve_re(curve_re),.curve_raddr(curve_raddr),.curve_rdata(curve_rdata),
   .clk(clk),.resetn(resetn),.s_data(s_data),.s_valid(s_valid),.s_sof(s_sof),.s_eol(s_eol),
   .s_packet_error(s_packet_error),.s_global_fault(s_global_fault),
   .m_data(m_data),.m_valid(m_valid),.m_sof(m_sof),.m_eol(m_eol),.m_ready(1'b1),
   .m_fault(m_global_fault),.fault_count(fault_count),.fifo_level(fifo_level));
  assign m_packet_error=1'b0;
 end else begin: legacy
  reg packet_d,fault_d;
  always @(posedge clk)if(!resetn)begin packet_d<=0;fault_d<=0;end
   else begin packet_d<=s_packet_error;fault_d<=s_global_fault;end
  raw10_to_yuy2 converter(.clk(clk),.resetn(resetn),.s_data(s_data),.s_valid(s_valid),
   .s_sof(s_sof),.s_eol(s_eol),.s_ready(),.m_data(m_data),.m_valid(m_valid),
   .m_sof(m_sof),.m_eol(m_eol),.m_ready(1'b1));
  assign m_packet_error=packet_d;
  assign m_global_fault=fault_d;
  assign fault_count=0;
  assign fifo_level=0;
 end endgenerate
 assign m_fault=m_packet_error|m_global_fault;
endmodule
