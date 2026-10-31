`timescale 1ns/1ps
// Broadcast CSI source -> buffered/stallable LTM. Any source discontinuity
// invalidates the capture and resets all queued/spatial state before next SOF.
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
 localparam integer PAIRS=WIDTH/2,YBITS=$clog2(HEIGHT+1);
 reg [3:0] holdoff;
 reg accepting,seen_sof;
 reg [9:0] input_x;
 reg [YBITS-1:0] input_y;
 reg [11:0] wrptr,rdptr;
 reg [12:0] count;
 reg head_valid;
 wire [21:0] head_data;
 wire processor_ready;
 reg frame_inflight;
 reg [YBITS-1:0] output_row;
 wire head_sof=head_valid&&head_data[21];
 wire boundary_hold=RUNTIME_CONFIG&&head_sof&&(frame_inflight||cfg_pending);
 wire processor_valid=head_valid&&!boundary_hold;
 assign frame_busy=frame_inflight;
 assign frame_done=m_valid&&m_ready&&m_eol&&(output_row==HEIGHT-1);
 assign cfg_safe=!frame_inflight&&(head_valid ? head_data[21] : count==0);
 always @(posedge clk) begin
  if(!pipeline_resetn)begin frame_inflight<=0;output_row<=0;end
  else begin
   if(processor_valid&&processor_ready&&head_data[21])frame_inflight<=1;
   if(m_valid&&m_ready)begin
    if(m_sof)output_row<=0;
    if(m_eol)begin
     if(output_row==HEIGHT-1)begin frame_inflight<=0;output_row<=0;end
     else output_row<=output_row+1'b1;
    end
   end
  end
 end
 wire available=(holdoff==0);
 wire starts=s_valid&&s_sof&&!accepting;
 wire selected=s_valid&&(accepting||starts);
 wire bad_marker=s_valid && (
     (accepting && (s_sof || s_eol!==(input_x==PAIRS-1))) ||
     (starts && s_eol) || (!accepting && !s_sof && seen_sof));
 wire overflow=selected && count==13'd4096;
 wire error_now=resetn&&available&&(s_global_fault||s_packet_error||bad_marker||overflow);
 wire pipeline_resetn=resetn&&available&&!error_now&&!s_global_fault;
 assign m_fault=resetn&&(!available||error_now||s_global_fault);
 wire write_enable=pipeline_resetn&&selected;
 wire head_advance=!head_valid||(processor_ready&&!boundary_hold);
 wire read_enable=pipeline_resetn&&head_advance&&(count!=0);
 assign fifo_level=count+head_valid;

 ltm_ingress_bram input_memory(
  .clka(clk),.ena(write_enable),.wea(write_enable),.addra(wrptr),.dina({s_sof,s_eol,s_data}),
  .clkb(clk),.enb(read_enable),.addrb(rdptr),.doutb(head_data));

 always @(posedge clk) begin
  if(!resetn)begin
   holdoff<=15;accepting<=0;seen_sof<=0;input_x<=0;input_y<=0;fault_count<=0;
  end else if(s_global_fault||error_now)begin
   holdoff<=15;accepting<=0;seen_sof<=0;input_x<=0;input_y<=0;
   if(available)fault_count<=fault_count+1'b1;
  end else if(!available)begin
   holdoff<=holdoff-1'b1;accepting<=0;seen_sof<=0;input_x<=0;input_y<=0;
  end else if(write_enable)begin
   if(starts)begin accepting<=1;seen_sof<=1;input_x<=1;input_y<=0;end
   else if(input_x==PAIRS-1)begin
    input_x<=0;
    if(input_y==HEIGHT-1)begin accepting<=0;input_y<=0;end
    else input_y<=input_y+1'b1;
   end else input_x<=input_x+1'b1;
  end
 end
 always @(posedge clk)begin
  if(!pipeline_resetn)begin wrptr<=0;rdptr<=0;count<=0;head_valid<=0;end
  else begin
   if(write_enable)wrptr<=wrptr+1'b1;
   if(read_enable)rdptr<=rdptr+1'b1;
   if(head_advance)head_valid<=(count!=0);
   case({write_enable,read_enable})
    2'b10:count<=count+1'b1;
    2'b01:count<=count-1'b1;
    default:;
   endcase
  end
 end
 ltm_processor #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.DETAIL_GAIN_Q8(DETAIL_GAIN_Q8),.RUNTIME_CONFIG(RUNTIME_CONFIG)) processor(
  .cfg_mode(cfg_mode),.cfg_range(cfg_range),.cfg_black(cfg_black),.cfg_gain(cfg_gain),.cfg_tone_enable(cfg_tone_enable),
  .cfg_bank(cfg_bank),.curve_we(curve_we),.curve_re(curve_re),.curve_waddr(curve_waddr),
  .curve_wdata(curve_wdata),.curve_raddr(curve_raddr),.curve_rdata(curve_rdata),
  .clk(clk),.resetn(pipeline_resetn),.s_data(head_data[19:0]),.s_valid(processor_valid),
  .s_sof(head_data[21]),.s_eol(head_data[20]),.s_ready(processor_ready),
  .m_data(m_data),.m_valid(m_valid),.m_sof(m_sof),.m_eol(m_eol),.m_ready(m_ready),
  .m_original(),.m_base(),.m_detail(),.m_reconstructed());

 // synthesis translate_off
 always @(posedge clk)if(pipeline_resetn)begin
  if(count>4096)$fatal(1,"INGRESS_COUNT_OVERFLOW");
  if(write_enable&&read_enable&&wrptr==rdptr)$fatal(1,"INGRESS_BRAM_COLLISION");
 end
 // synthesis translate_on
endmodule
