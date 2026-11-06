`timescale 1ns/1ps
module tb_full;
localparam W=1280,H=1024,N=W*H/2;
reg clk=0; always #5 clk=~clk;
reg resetn=0,valid=0,sof=0,eol=0,fault=0,yr=1,ur=1;
reg [31:0] d=0;
wire [15:0] yd,ud; wire yv,uv,ys,ye,yf,us,ue,uf,abort,done;
integer sent=0,yc=0,uc=0,dc=0,ac=0,cy=0;
reg [31:0] rng=32'h12345678;
function [7:0] sample(input integer f,input integer y,input integer x,input integer c);
 sample=(f*37+y*13+x*7+c*53) & 255;
endfunction
isp_yuy2_nv12 #(.WIDTH(W),.HEIGHT(H)) dut(clk,resetn,d,valid,sof,eol,fault,yd,yv,ys,ye,yf,yr,ud,uv,us,ue,uf,ur,abort,done);
always @(posedge clk) if(resetn) begin : check
 integer f,r,x,a,b;
 if(yv&&yr) begin
  f=yc/N;r=(yc%N)/(W/2);x=(yc%(W/2))*2;
  if(yd !== {sample(f,r,x+1,0),sample(f,r,x,0)} || ys!==(r==0&&x==0) || ye!==(x==W-2) || yf!==(r==H-1&&x==W-2)) $fatal(1,"Y mismatch %d",yc);
  yc=yc+1;
 end
 if(uv&&ur) begin
  f=uc/(N/2);r=((uc%(N/2))/(W/2))*2;x=(uc%(W/2))*2;
  a=(sample(f,r,x,1)+sample(f,r+1,x,1)+1)/2;
  b=(sample(f,r,x,2)+sample(f,r+1,x,2)+1)/2;
  if(ud !== {b[7:0],a[7:0]} || us!==(r==0&&x==0) || ue!==(x==W-2) || uf!==(r==H-2&&x==W-2)) $fatal(1,"UV mismatch %d",uc);
  uc=uc+1;
 end
 if(abort) begin ac=ac+1;$fatal(1,"unexpected abort");end
 if(done) dc=dc+1;
end
initial begin : stimulus
 integer f,r,x;
 repeat(3) @(negedge clk);resetn=1;
 while(sent<2*N) begin
  @(negedge clk);
  rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
  // Backpressure occurs only during input bubbles, so no output is lost.
  valid=(rng[3:0]!=0);yr=1;ur=1;
  if(!valid) begin yr=rng[5];ur=rng[6];end
  f=sent/N;r=(sent%N)/(W/2);x=(sent%(W/2))*2;
  sof=valid&&(r==0)&&(x==0);eol=valid&&(x==W-2);
  d={sample(f,r,x,2),sample(f,r,x+1,0),sample(f,r,x,1),sample(f,r,x,0)};
  if(valid) sent=sent+1;
 end
 @(negedge clk);valid=0;yr=1;ur=1;sof=0;eol=0;
 repeat(8) @(negedge clk);
 if(yc!=2*N||uc!=N||dc!=2||ac!=0) $fatal(1,"counts y=%d uv=%d done=%d",yc,uc,dc);
 $display("PASS full frames Y=%0d UV=%0d done=%0d",yc,uc,dc);$finish;
end
endmodule
