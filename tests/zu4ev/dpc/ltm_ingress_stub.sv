`timescale 1ns/1ps
// Test double: observe the actual frontend RAW output without tone conversion.
module ltm_camera_ingress #(
 parameter integer WIDTH=1280,HEIGHT=1024,DETAIL_GAIN_Q8=256,RUNTIME_CONFIG=0
)(
 input wire clk,resetn,
 input wire cfg_pending,
 input wire [1:0] cfg_mode,cfg_range,
 input wire [9:0] cfg_black,cfg_gain,
 input wire cfg_bank,curve_we,curve_re,cfg_tone_enable,
 input wire [9:0] curve_waddr,curve_wdata,curve_raddr,
 output wire [9:0] curve_rdata,
 output wire cfg_safe,frame_busy,frame_done,
 input wire [19:0] s_data,
 input wire s_valid,s_sof,s_eol,s_packet_error,s_global_fault,
 output wire [31:0] m_data,
 output wire m_valid,m_sof,m_eol,
 input wire m_ready,
 output wire m_fault,
 output reg [31:0] fault_count,
 output wire [12:0] fifo_level
);
 assign m_data={12'd0,s_data};
 assign m_valid=s_valid;
 assign m_sof=s_sof;
 assign m_eol=s_eol;
 assign m_fault=s_packet_error||s_global_fault;
 assign fault_count=0;
 assign fifo_level=0;
 assign cfg_safe=1;
 assign frame_busy=0;
 assign frame_done=0;
 assign curve_rdata=0;
endmodule
