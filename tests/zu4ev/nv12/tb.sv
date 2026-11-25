`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg resetn=0;reg [31:0] d=0;reg valid=0,sof=0,eol=0,fault=0,yr=1,ur=1;
wire [15:0] yd,ud;wire yv,uv,ys,ye,yf,us,ue,uf,abort,done;
integer yc=0,uc=0,dc=0,ac=0,i;
isp_yuy2_nv12 #(.WIDTH(4),.HEIGHT(2)) dut(clk,resetn,d,valid,sof,eol,fault,yd,yv,ys,ye,yf,yr,ud,uv,us,ue,uf,ur,abort,done);
always @(posedge clk) if(resetn) begin
 if(yv&&yr) begin
  if(yd!==16'h0301 || ys!==(yc==0) || ye!==(yc%2==1) || yf!==(yc==3)) $fatal(1,"Y mismatch");
  yc=yc+1;
 end
 if(uv&&ur) begin
  if(ud!==16'h0905 || us!==(uc==0) || ue!==(uc==1) || uf!==(uc==1)) $fatal(1,"UV mismatch");
  uc=uc+1;
 end
 if(done) dc=dc+1;
 if(abort) ac=ac+1;
end
initial begin
 repeat(3) @(negedge clk);resetn=1;
 for(i=0;i<4;i=i+1) begin
  @(negedge clk);valid=1;sof=(i==0);eol=(i%2==1);d=(i<2)?32'h08030201:32'h09030701;
 end
 @(negedge clk);valid=0;sof=0;eol=0;
 repeat(5) @(negedge clk);
 if(yc!=4||uc!=2||dc!=1||ac!=0) $fatal(1,"counts");
 // Block Y: preserve pending payload and abort on next input.
 yr=0;valid=1;sof=1;d=32'h08030201;
 @(negedge clk);sof=0;eol=1;
 @(negedge clk);valid=0;eol=0;
 repeat(3) @(negedge clk);
 if(ac!=1||!yv||yd!==16'h0301) $fatal(1,"stall abort");
 resetn=0;
 @(negedge clk);if(yv||uv) $fatal(1,"reset");
 $display("PASS NV12 pixels markers completion stall abort reset");$finish;
end
initial begin #2000;$fatal(1,"timeout");end
endmodule
