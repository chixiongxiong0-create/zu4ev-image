`timescale 1ns/1ps
module isp_axi_regs #(parameter WIDTH=1280, HEIGHT=720, AE_STATS=0, FFC=0, DPC=0)(
 input wire clk,resetn,
 output wire ffc_write, output wire ffc_read,
 output wire [15:0] ffc_waddr, output wire [15:0] ffc_raddr,
 output wire [31:0] ffc_wdata,
 input wire ffc_write_ok, input wire [31:0] ffc_rdata,
 input wire [15:0] s_axi_awaddr,input wire s_axi_awvalid,output wire s_axi_awready,
 input wire [31:0] s_axi_wdata,input wire [3:0] s_axi_wstrb,input wire s_axi_wvalid,output wire s_axi_wready,
 output reg [1:0] s_axi_bresp,output reg s_axi_bvalid,input wire s_axi_bready,
 input wire [15:0] s_axi_araddr,input wire s_axi_arvalid,output wire s_axi_arready,
 output reg [31:0] s_axi_rdata,output reg [1:0] s_axi_rresp,output reg s_axi_rvalid,input wire s_axi_rready,
 input wire cfg_safe,frame_busy,frame_done,input wire [31:0] fault_count,input wire [12:0] fifo_level,
 output reg cfg_pending,output reg [1:0] cfg_mode,output reg [9:0] cfg_black,cfg_gain,
 output reg [1:0] cfg_range,output reg cfg_bank,output reg cfg_tone_enable,
 output reg curve_we,output reg [9:0] curve_waddr,curve_wdata,
 output wire curve_re,output wire [9:0] curve_raddr,input wire [9:0] curve_rdata,
 output reg ae_enable,output reg [1:0] ae_region,output reg [9:0] ae_black,
 input wire ae_valid,ae_busy,ae_active,
 input wire [31:0] ae_seq,ae_frame,ae_mean,ae_count,ae_bad,ae_overrun,
 input wire [47:0] ae_sum,input wire [1:0] ae_result_region,input wire [9:0] ae_result_black,
 input wire [31:0] ae_x,ae_y,ae_width,ae_height
);
 reg aw_full,w_full; reg [15:0] aw; reg [31:0] wd; reg [3:0] ws;
 reg [31:0] shadow_mode,shadow_black,shadow_gain,shadow_range;
 reg shadow_blc_enable, pending_blc_enable, active_blc_enable;
 reg shadow_tone_enable, pending_tone_enable;
 reg [1:0] pending_mode,pending_range; reg [9:0] pending_black,pending_gain; reg pending_swap;
 reg [31:0] applied_seq,frame_count; reg read_wait;
 reg ae_control_enable;
 // Shared synchronous correction-register bridge; FFC addresses are unchanged.
 wire ffc_ar=s_axi_araddr[1:0]==0 && ((FFC && (
  (s_axi_araddr>=16'h3000 && s_axi_araddr<=16'h3024) ||
  (s_axi_araddr>=16'h3040 && s_axi_araddr<=16'h304c) || s_axi_araddr==16'h3050 ||
  (s_axi_araddr>=16'h4000 && s_axi_araddr<16'h4000+4*(WIDTH/32+1)*(HEIGHT/32+1)) ||
  (s_axi_araddr>=16'h6000 && s_axi_araddr<16'h6000+4*(WIDTH/32)*(HEIGHT/32)))) ||
  (DPC && ((s_axi_araddr>=16'h3100 && s_axi_araddr<=16'h3154) ||
   (s_axi_araddr>=16'h8000 && s_axi_araddr<16'h9000) ||
   (s_axi_araddr>=16'ha000 && s_axi_araddr<16'hc000))));
 wire ffc_aw=(FFC && ((aw>=16'h3000 && aw<16'h3100)||(aw>=16'h4000 && aw<16'h6000))) ||
  (DPC && ((aw>=16'h3100 && aw<16'h3160)||(aw>=16'h8000 && aw<16'h9000)));
 reg read_ffc;
 assign ffc_read=s_axi_arvalid && s_axi_arready && ffc_ar;
 assign ffc_raddr=s_axi_araddr;
 assign ffc_waddr=aw; assign ffc_wdata=wd;
 assign ffc_write=resetn && aw_full && w_full && !s_axi_bvalid && !read_wait &&
  !s_axi_rvalid && !curve_re && ffc_aw && aw[1:0]==0 && ws==4'hf;
 wire lut_ar=s_axi_araddr>=16'h1000 && s_axi_araddr<=16'h1ffc && s_axi_araddr[1:0]==0;
 assign s_axi_awready=resetn && !aw_full && !s_axi_bvalid;
 assign s_axi_wready=resetn && !w_full && !s_axi_bvalid;
 wire applying=cfg_pending && cfg_safe && !read_wait && !s_axi_rvalid && !curve_we;
 assign s_axi_arready=resetn && !s_axi_rvalid && !read_wait && !curve_we && !(aw_full && w_full) && !(applying && lut_ar);
 assign curve_re=s_axi_arvalid && s_axi_arready && lut_ar;
 assign curve_raddr=s_axi_araddr[11:2];
 function automatic [31:0] merge(input [31:0] oldv,input [31:0] newv,input [3:0] strb);
 integer i; begin merge=oldv; for(i=0;i<4;i=i+1) if(strb[i]) merge[i*8+:8]=newv[i*8+:8]; end endfunction
 reg [31:0] merged;
 always @(posedge clk) begin
 if(!resetn) begin
 read_ffc<=0;
 ae_enable<=1;ae_region<=3;ae_black<=52;ae_control_enable<=1;
 aw_full<=0;w_full<=0;aw<=0;wd<=0;ws<=0;s_axi_bvalid<=0;s_axi_bresp<=0;
 s_axi_rvalid<=0;s_axi_rresp<=0;s_axi_rdata<=0;read_wait<=0;
 shadow_mode<=0;shadow_black<=52;shadow_gain<=256;shadow_range<=0;
 shadow_blc_enable<=1;pending_blc_enable<=1;active_blc_enable<=1;
 shadow_tone_enable<=1;pending_tone_enable<=1;cfg_tone_enable<=1;
 cfg_mode<=0;cfg_black<=52;cfg_gain<=256;cfg_range<=0;cfg_bank<=0;cfg_pending<=0;
 pending_mode<=0;pending_black<=52;pending_gain<=256;pending_range<=0;pending_swap<=0;
 applied_seq<=0;frame_count<=0;curve_we<=0;curve_waddr<=0;curve_wdata<=0;
 end else begin
 curve_we<=0;
 if(frame_done) frame_count<=frame_count+1;
 if(s_axi_bvalid && s_axi_bready) s_axi_bvalid<=0;
 if(s_axi_rvalid && s_axi_rready) s_axi_rvalid<=0;
 if(s_axi_awvalid && s_axi_awready) begin aw<=s_axi_awaddr;aw_full<=1;end
 if(s_axi_wvalid && s_axi_wready) begin wd<=s_axi_wdata;ws<=s_axi_wstrb;w_full<=1;end
 if(cfg_pending && cfg_safe && !read_wait && !s_axi_rvalid && !curve_re && !curve_we) begin
 cfg_mode<=pending_mode;cfg_black<=pending_blc_enable ? pending_black : 10'd0;cfg_gain<=pending_gain;cfg_range<=pending_range;
 active_blc_enable<=pending_blc_enable;
 cfg_tone_enable<=pending_tone_enable;
 if(pending_swap) cfg_bank<=!cfg_bank;
 cfg_pending<=0;applied_seq<=applied_seq+1;
 end
 // A coefficient response owns the inactive bank through its R handshake.
 if(aw_full && w_full && !s_axi_bvalid && !read_wait && !s_axi_rvalid && !curve_re) begin
 aw_full<=0;w_full<=0;s_axi_bvalid<=1;s_axi_bresp<=0;
 if(aw[1:0]!=0) s_axi_bresp<=2;
 else if(ffc_aw) begin
 if(ws!=4'hf || !ffc_write_ok) s_axi_bresp<=2;
 end
 else if(aw>=16'h1000 && aw<=16'h1ffc) begin
 if(cfg_pending || ws!=4'hf || wd>1023) s_axi_bresp<=2;
 else begin curve_we<=1;curve_waddr<=aw[11:2];curve_wdata<=wd[9:0];end
 end else case(aw)
 16'h248: begin
 merged=merge({31'b0,ae_control_enable},wd,ws);
 if(!AE_STATS || merged>1) s_axi_bresp<=2;else ae_control_enable<=merged[0];
 end
 16'h208: begin
 merged=merge({29'b0,ae_region,ae_enable},wd,ws);
 if(!AE_STATS || merged>7) s_axi_bresp<=2;else begin ae_enable<=merged[0];ae_region<=merged[2:1];end
 end
 16'h20c: begin
 merged=merge({22'b0,ae_black},wd,ws);
 if(!AE_STATS || merged>1023) s_axi_bresp<=2;else ae_black<=merged[9:0];
 end
 16'h10: begin merged=merge(shadow_mode,wd,ws);if(merged>3) s_axi_bresp<=2;else shadow_mode<=merged;end
 16'h14: begin merged=merge(shadow_black,wd,ws);if(merged>1022) s_axi_bresp<=2;else shadow_black<=merged;end
 16'h18: begin merged=merge(shadow_gain,wd,ws);if(merged>512) s_axi_bresp<=2;else shadow_gain<=merged;end
 16'h1c: begin merged=merge(shadow_range,wd,ws);if(merged>2) s_axi_bresp<=2;else shadow_range<=merged;end
 16'h5c: begin merged=merge({31'b0,shadow_blc_enable},wd,ws);if(merged>1) s_axi_bresp<=2;else shadow_blc_enable<=merged[0];end
 16'h64: begin merged=merge({31'b0,shadow_tone_enable},wd,ws);if(merged>1) s_axi_bresp<=2;else shadow_tone_enable<=merged[0];end
 16'h20: begin
 merged=merge(0,wd,ws);
 if(merged>3 || merged==2 || (merged[0] && cfg_pending)) s_axi_bresp<=2;
 else if(merged[0]) begin cfg_pending<=1;pending_mode<=shadow_mode[1:0];pending_black<=shadow_black[9:0];pending_gain<=shadow_gain[9:0];pending_range<=shadow_range[1:0];pending_swap<=merged[1];pending_blc_enable<=shadow_blc_enable;pending_tone_enable<=shadow_tone_enable;end
 end
 default:s_axi_bresp<=2;
 endcase
 end
 if(read_wait) begin s_axi_rdata<=read_ffc ? ffc_rdata : {22'b0,curve_rdata};s_axi_rresp<=0;s_axi_rvalid<=1;read_wait<=0;end
 if(s_axi_arvalid && s_axi_arready) begin
 s_axi_rdata<=0;s_axi_rresp<=0;
 if(lut_ar || ffc_ar) begin read_wait<=1;read_ffc<=ffc_ar;end
 else begin
 s_axi_rvalid<=1;
 if(s_axi_araddr[1:0]!=0) s_axi_rresp<=2;
 else case(s_axi_araddr)
 16'h00:s_axi_rdata<=32'h49535031;16'h04:s_axi_rdata<=32'h00010000;
 16'h08:s_axi_rdata<=AE_STATS?32'h000000ff:32'h000000cf;
 16'h0c:s_axi_rdata<={29'b0,frame_busy,cfg_bank,cfg_pending};
 16'h10:s_axi_rdata<=shadow_mode;16'h14:s_axi_rdata<=shadow_black;16'h18:s_axi_rdata<=shadow_gain;16'h1c:s_axi_rdata<=shadow_range;
 16'h20:s_axi_rdata<=0;16'h24:s_axi_rdata<=applied_seq;16'h28:s_axi_rdata<=frame_count;
 16'h2c:s_axi_rdata<=fault_count;16'h30:s_axi_rdata<={19'b0,fifo_level};
 16'h34:s_axi_rdata<={30'b0,cfg_mode};16'h38:s_axi_rdata<={22'b0,cfg_black};16'h3c:s_axi_rdata<={22'b0,cfg_gain};16'h40:s_axi_rdata<={30'b0,cfg_range};
 16'h48:s_axi_rdata<=WIDTH;16'h4c:s_axi_rdata<=HEIGHT;16'h50:s_axi_rdata<=32'h00050005;16'h58:s_axi_rdata<=1024;
 16'h5c:s_axi_rdata<={31'b0,shadow_blc_enable};16'h60:s_axi_rdata<={31'b0,active_blc_enable};
 16'h64:s_axi_rdata<={31'b0,shadow_tone_enable};16'h68:s_axi_rdata<={31'b0,cfg_tone_enable};
 16'h200:begin if(AE_STATS) s_axi_rdata<=32'h41455331;else s_axi_rresp<=2;end
 16'h204:begin if(AE_STATS) s_axi_rdata<=32'h00010000;else s_axi_rresp<=2;end
 16'h208:begin if(AE_STATS) s_axi_rdata<={29'b0,ae_region,ae_enable};else s_axi_rresp<=2;end
 16'h20c:begin if(AE_STATS) s_axi_rdata<={22'b0,ae_black};else s_axi_rresp<=2;end
 16'h210:begin if(AE_STATS) s_axi_rdata<={29'b0,ae_active,ae_busy,ae_valid};else s_axi_rresp<=2;end
 16'h214:begin if(AE_STATS) s_axi_rdata<=ae_seq;else s_axi_rresp<=2;end
 16'h218:begin if(AE_STATS) s_axi_rdata<=ae_frame;else s_axi_rresp<=2;end
 16'h21c:begin if(AE_STATS) s_axi_rdata<=ae_mean;else s_axi_rresp<=2;end
 16'h220:begin if(AE_STATS) s_axi_rdata<=ae_count;else s_axi_rresp<=2;end
 16'h224:begin if(AE_STATS) s_axi_rdata<=ae_sum[31:0];else s_axi_rresp<=2;end
 16'h228:begin if(AE_STATS) s_axi_rdata<={16'b0,ae_sum[47:32]};else s_axi_rresp<=2;end
 16'h22c:begin if(AE_STATS) s_axi_rdata<=ae_bad;else s_axi_rresp<=2;end
 16'h230:begin if(AE_STATS) s_axi_rdata<=ae_overrun;else s_axi_rresp<=2;end
 16'h234:begin if(AE_STATS) s_axi_rdata<={14'b0,ae_result_black,6'b0,ae_result_region};else s_axi_rresp<=2;end
 16'h238:begin if(AE_STATS) s_axi_rdata<=ae_x;else s_axi_rresp<=2;end
 16'h23c:begin if(AE_STATS) s_axi_rdata<=ae_y;else s_axi_rresp<=2;end
 16'h240:begin if(AE_STATS) s_axi_rdata<=ae_width;else s_axi_rresp<=2;end
 16'h244:begin if(AE_STATS) s_axi_rdata<=ae_height;else s_axi_rresp<=2;end
 16'h248:begin if(AE_STATS) s_axi_rdata<={31'b0,ae_control_enable};else s_axi_rresp<=2;end
 default:s_axi_rresp<=2;
 endcase
 end
 end
 end
 end
endmodule

