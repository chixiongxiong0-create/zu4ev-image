`timescale 1ns/1ps
// Passive RAW10 observer. A beat always contains two pixels, low pixel first.
module ae_stats_raw10 #(parameter integer WIDTH=1280, HEIGHT=1024)(
 input wire clk,resetn,input wire [19:0] s_data,
 input wire s_valid,s_sof,s_eol,s_packet_error,s_global_fault,
 input wire cfg_enable,input wire [1:0] cfg_region,input wire [9:0] cfg_black,
 output reg result_valid,output reg div_busy,output reg active_enable,
 output reg [31:0] result_seq,result_frame,result_mean,result_count,bad_frames,overruns,
 output reg [47:0] result_sum,output reg [1:0] result_region,
 output reg [9:0] result_black,output reg [31:0] roi_x,roi_y,roi_width,roi_height
);
 // Exact integer construction: k=floor(d*sqrt(n/4)/2), width=2*k.
 // All calls are elaboration constants; there is no runtime square root.
 function automatic integer extent(input integer d,input integer n);
  reg [63:0] target,trial; integer lo,hi,mid,j;
  begin
   target=d;target=target*d*n;lo=0;hi=d/2;
   for(j=0;j<32;j=j+1) begin
    mid=(lo+hi+1)/2;trial=mid;trial=trial*mid*16;
    if(trial<=target) lo=mid;else hi=mid-1;
   end
   extent=(lo<1)?2:2*lo;
  end
 endfunction
 localparam W0=extent(WIDTH,1),W1=extent(WIDTH,2),W2=extent(WIDTH,3),W3=extent(WIDTH,4);
 localparam H0=extent(HEIGHT,1),H1=extent(HEIGHT,2),H2=extent(HEIGHT,3),H3=extent(HEIGHT,4);
 function automatic [31:0] region_w(input [1:0] r);
  case(r) 0:region_w=W0;1:region_w=W1;2:region_w=W2;default:region_w=W3;endcase
 endfunction
 function automatic [31:0] region_h(input [1:0] r);
  case(r) 0:region_h=H0;1:region_h=H1;2:region_h=H2;default:region_h=H3;endcase
 endfunction
 reg collecting,completed,poisoned;reg [31:0] x,y,input_frame;
 reg [1:0] locked_region;reg [9:0] locked_black;
 reg [31:0] rx,ry,rw,rh;reg [47:0] sum;reg [31:0] count;
 wire start=s_valid&&s_sof;
 wire en=start?cfg_enable:active_enable;
 wire [9:0] black=start?cfg_black:locked_black;
 wire [31:0] bw=start?region_w(cfg_region):rw,bh=start?region_h(cfg_region):rh;
 wire [31:0] bx=start?(WIDTH-bw)/2:rx,by=start?(HEIGHT-bh)/2:ry;
 wire [31:0] px=start?0:x,py=start?0:y;
 wire hit0=(px>=bx)&&(px<bx+bw)&&(py>=by)&&(py<by+bh);
 wire hit1=(px+1>=bx)&&(px+1<bx+bw)&&(py>=by)&&(py<by+bh);
 wire [9:0] v0=s_data[9:0]>black?s_data[9:0]-black:10'd0;
 wire [9:0] v1=s_data[19:10]>black?s_data[19:10]-black:10'd0;
 wire [47:0] next_sum=(start?48'd0:sum)+(hit0?{38'd0,v0}:48'd0)+(hit1?{38'd0,v1}:48'd0);
 wire [31:0] next_count=(start?32'd0:count)+(hit0?32'd1:32'd0)+(hit1?32'd1:32'd0);
 wire malformed=(px+2>WIDTH)||(py>=HEIGHT)||(s_eol!=(px+2==WIDTH));
 wire fault=s_packet_error||s_global_fault;
 // A frame remains attributable until the next SOF, including CSI trailer
 // errors and excess rows. A new SOF assigns faults to the new frame only.
 wire late_fault=completed&&!start&&(s_valid||fault);
 reg [47:0] dividend,quotient,held_sum;
 reg [32:0] remainder;reg [31:0] divisor;
 reg [5:0] step;
 reg [31:0] held_frame,held_x,held_y,held_w,held_h;
 reg [1:0] held_region;reg [9:0] held_black;
 wire [32:0] shifted_rem={remainder[31:0],dividend[47]};
 wire subtract=shifted_rem>={1'b0,divisor};
 wire [47:0] next_quotient={quotient[46:0],subtract};
 always @(posedge clk) begin
  if(!resetn) begin
   collecting<=0;completed<=0;poisoned<=0;x<=0;y<=0;input_frame<=0;active_enable<=0;
   locked_region<=3;locked_black<=52;rx<=0;ry<=0;rw<=0;rh<=0;sum<=0;count<=0;
   result_valid<=0;div_busy<=0;result_seq<=0;result_frame<=0;result_mean<=0;result_count<=0;
   bad_frames<=0;overruns<=0;result_sum<=0;result_region<=0;result_black<=0;
   roi_x<=0;roi_y<=0;roi_width<=0;roi_height<=0;
   dividend<=0;quotient<=0;held_sum<=0;remainder<=0;divisor<=0;step<=0;
   held_frame<=0;held_x<=0;held_y<=0;held_w<=0;held_h<=0;held_region<=0;held_black<=0;
  end else begin
   if(div_busy && !(late_fault && held_frame==input_frame)) begin
    dividend<={dividend[46:0],1'b0};quotient<=next_quotient;
    remainder<=subtract?shifted_rem-{1'b0,divisor}:shifted_rem;
    if(step==47) begin
     div_busy<=0;result_valid<=1;result_seq<=result_seq+1;result_frame<=held_frame;
     result_mean<=next_quotient[31:0];result_count<=divisor;result_sum<=held_sum;
     result_region<=held_region;result_black<=held_black;
     roi_x<=held_x;roi_y<=held_y;roi_width<=held_w;roi_height<=held_h;
    end else step<=step+1;
   end
   if(late_fault) begin
    poisoned<=1;
    if(!poisoned) bad_frames<=bad_frames+1;
    if(div_busy&&held_frame==input_frame) div_busy<=0;
    if(result_valid&&result_frame==input_frame) result_valid<=0;
   end
   // Fault flags may arrive on an idle cycle. Count each damaged frame once.
   if(fault&&collecting&&!poisoned&&!start) begin poisoned<=1;bad_frames<=bad_frames+1;end
   if(start) begin
    input_frame<=input_frame+1;active_enable<=cfg_enable;locked_region<=cfg_region;locked_black<=cfg_black;
    rx<=bx;ry<=by;rw<=bw;rh<=bh;collecting<=1;completed<=0;poisoned<=0;
    if(collecting&&!poisoned) bad_frames<=bad_frames+1;
   end
   if(s_valid&&(collecting||start)) begin
    sum<=next_sum;count<=next_count;
    if(s_eol) begin x<=0;y<=py+1;end else begin x<=px+2;y<=py;end
    if(fault||malformed) begin
     poisoned<=1;
     if(start) bad_frames<=bad_frames+((collecting&&!poisoned)?2:1);
     else if(!poisoned) bad_frames<=bad_frames+1;
    end
    if(s_eol&&py==HEIGHT-1) begin
     collecting<=0;completed<=1;
     if(en&&!(start?1'b0:poisoned)&&!fault&&!malformed) begin
      if(div_busy) overruns<=overruns+1;
      else begin
       div_busy<=1;step<=0;dividend<=next_sum;held_sum<=next_sum;divisor<=next_count;
       quotient<=0;remainder<=0;held_frame<=start?input_frame+1:input_frame;
       held_region<=start?cfg_region:locked_region;held_black<=black;
       held_x<=bx;held_y<=by;held_w<=bw;held_h<=bh;
      end
     end
    end
   end
  end
 end
endmodule
