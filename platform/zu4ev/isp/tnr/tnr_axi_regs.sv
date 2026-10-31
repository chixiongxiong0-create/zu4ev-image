`timescale 1ns/1ps
module tnr_axi_regs #(
 parameter integer WIDTH=1280, HEIGHT=1024
)(
 input wire clk, resetn,
 input wire [15:0] s_axi_awaddr, input wire s_axi_awvalid, output wire s_axi_awready,
 input wire [31:0] s_axi_wdata, input wire [3:0] s_axi_wstrb,
 input wire s_axi_wvalid, output wire s_axi_wready,
 output reg [1:0] s_axi_bresp, output reg s_axi_bvalid, input wire s_axi_bready,
 input wire [15:0] s_axi_araddr, input wire s_axi_arvalid, output wire s_axi_arready,
 output reg [31:0] s_axi_rdata, output reg [1:0] s_axi_rresp,
 output reg s_axi_rvalid, input wire s_axi_rready,
 input wire cfg_safe, history_valid, busy, calib_done, memtest_busy, memtest_done,
 input wire [31:0] memtest_errors, frame_count, motion_count, filtered_count,
 input wire [31:0] fault_count, ddr_error_count,
 input wire [15:0] fifo_level,
 output reg cfg_enable, cfg_pending, cfg_clear_history, memtest_start,
 output reg [8:0] cfg_alpha,
 output reg [7:0] cfg_motion_lo, cfg_motion_hi
);
 reg aw_full, w_full;
 reg [15:0] aw_addr;
 reg [31:0] w_data;
 reg [3:0] w_strb;
 reg [31:0] shadow_enable, shadow_alpha, shadow_lo, shadow_hi, applied_seq;
 reg pending_enable;
 reg [8:0] pending_alpha;
 reg [7:0] pending_lo, pending_hi;
 reg [31:0] merged;

 assign s_axi_awready = !aw_full && !s_axi_bvalid;
 assign s_axi_wready = !w_full && !s_axi_bvalid;
 assign s_axi_arready = !s_axi_rvalid || s_axi_rready;
 function automatic [31:0] merge_bytes(input [31:0] old_value, new_value, input [3:0] strobes);
 integer j;
 begin
 merge_bytes=old_value;
 for(j=0;j<4;j=j+1) if(strobes[j]) merge_bytes[j*8+:8]=new_value[j*8+:8];
 end
 endfunction
 always @(posedge clk) begin
 if(!resetn) begin
 aw_full<=0; w_full<=0; aw_addr<=0; w_data<=0; w_strb<=0;
 s_axi_bvalid<=0; s_axi_bresp<=0; s_axi_rvalid<=0; s_axi_rdata<=0; s_axi_rresp<=0;
 shadow_enable<=0; shadow_alpha<=192; shadow_lo<=6; shadow_hi<=20;
 cfg_enable<=0; cfg_alpha<=192; cfg_motion_lo<=6; cfg_motion_hi<=20;
 cfg_pending<=0; cfg_clear_history<=0; memtest_start<=0; applied_seq<=0;
 pending_enable<=0; pending_alpha<=192; pending_lo<=6; pending_hi<=20;
 end else begin
 cfg_clear_history<=0; memtest_start<=0;
 if(cfg_pending && cfg_safe) begin
 cfg_enable<=pending_enable; cfg_alpha<=pending_alpha;
 cfg_motion_lo<=pending_lo; cfg_motion_hi<=pending_hi;
 cfg_pending<=0; cfg_clear_history<=1; applied_seq<=applied_seq+1;
 end
 if(s_axi_awready && s_axi_awvalid) begin aw_full<=1; aw_addr<=s_axi_awaddr; end
 if(s_axi_wready && s_axi_wvalid) begin w_full<=1; w_data<=s_axi_wdata; w_strb<=s_axi_wstrb; end
 if(s_axi_bvalid && s_axi_bready) s_axi_bvalid<=0;
 if(aw_full && w_full && !s_axi_bvalid) begin
 aw_full<=0; w_full<=0; s_axi_bvalid<=1; s_axi_bresp<=0;
 if(aw_addr[1:0]!=0) s_axi_bresp<=2;
 else case(aw_addr)
 16'h10,16'h14,16'h18,16'h1c: begin
 case(aw_addr)
 16'h10: merged=merge_bytes(shadow_enable,w_data,w_strb);
 16'h14: merged=merge_bytes(shadow_alpha,w_data,w_strb);
 16'h18: merged=merge_bytes(shadow_lo,w_data,w_strb);
 default: merged=merge_bytes(shadow_hi,w_data,w_strb);
 endcase
 if(cfg_pending || (aw_addr==16'h10 && merged>1) ||
 (aw_addr==16'h14 && merged>256) || (aw_addr==16'h18 && merged>254) ||
 (aw_addr==16'h1c && (merged<1 || merged>255))) s_axi_bresp<=2;
 else case(aw_addr)
 16'h10: shadow_enable<=merged;
 16'h14: shadow_alpha<=merged;
 16'h18: shadow_lo<=merged;
 default: shadow_hi<=merged;
 endcase
 end
 16'h20: begin
 merged=merge_bytes(32'b0,w_data,w_strb);
 case(merged)
 0: begin end
 1,3: if(cfg_pending || shadow_lo>=shadow_hi) s_axi_bresp<=2;
 else begin
 cfg_pending<=1; pending_enable<=shadow_enable[0]; pending_alpha<=shadow_alpha[8:0];
 pending_lo<=shadow_lo[7:0]; pending_hi<=shadow_hi[7:0];
 end
 2: if(cfg_pending) s_axi_bresp<=2;
 else begin
 cfg_pending<=1; pending_enable<=cfg_enable; pending_alpha<=cfg_alpha;
 pending_lo<=cfg_motion_lo; pending_hi<=cfg_motion_hi;
 end
 4: if(cfg_enable || !calib_done || memtest_busy || cfg_pending) s_axi_bresp<=2;
 else memtest_start<=1;
 default: s_axi_bresp<=2;
 endcase
 end
 default: s_axi_bresp<=2;
 endcase
 end
 if(s_axi_arready) begin
 s_axi_rvalid<=s_axi_arvalid;
 if(s_axi_arvalid) begin
 s_axi_rresp<=0; s_axi_rdata<=0;
 if(s_axi_araddr[1:0]!=0) s_axi_rresp<=2;
 else case(s_axi_araddr)
 16'h00: s_axi_rdata<=32'h544e5231;
 16'h04: s_axi_rdata<=32'h00010000;
 16'h08: s_axi_rdata<=32'hf;
 16'h0c: s_axi_rdata<={26'b0,memtest_done,memtest_busy,busy,history_valid,calib_done,cfg_pending};
 16'h10: s_axi_rdata<=shadow_enable;
 16'h14: s_axi_rdata<=shadow_alpha;
 16'h18: s_axi_rdata<=shadow_lo;
 16'h1c: s_axi_rdata<=shadow_hi;
 16'h20: s_axi_rdata<=0;
 16'h24: s_axi_rdata<=applied_seq;
 16'h28: s_axi_rdata<=frame_count;
 16'h2c: s_axi_rdata<=motion_count;
 16'h30: s_axi_rdata<=filtered_count;
 16'h34: s_axi_rdata<=fault_count;
 16'h38: s_axi_rdata<=ddr_error_count;
 16'h3c: s_axi_rdata<={16'b0,fifo_level};
 16'h40: s_axi_rdata<={31'b0,cfg_enable};
 16'h44: s_axi_rdata<={23'b0,cfg_alpha};
 16'h48: s_axi_rdata<={24'b0,cfg_motion_lo};
 16'h4c: s_axi_rdata<={24'b0,cfg_motion_hi};
 16'h50: s_axi_rdata<=memtest_errors;
 16'h54: s_axi_rdata<=WIDTH;
 16'h58: s_axi_rdata<=HEIGHT;
 16'h5c: s_axi_rdata<=WIDTH*HEIGHT*2;
 16'h60: s_axi_rdata<=0;
 16'h64: s_axi_rdata<=32'h00400000;
 default: s_axi_rresp<=2;
 endcase
 end
 end
 end
 end
endmodule

