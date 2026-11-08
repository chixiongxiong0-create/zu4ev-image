`timescale 1ns/1ps
module tb_ffc;
 parameter W=64,H=64,FRAMES=32;
 localparam C=W/32+1,R=H/32+1,N=C*R,CELLS=(C-1)*(R-1);
 reg clk=0;always #2.5 clk=~clk;
 reg resetn=0;reg[19:0] sd=0;reg sv=0,ss=0,se=0,sp=0,sf=0;
 wire[19:0] md;wire mv,ms,me,mp,mf;
 reg cw=0,cr=0;reg[15:0] wa=0,ra=0;reg[31:0] wd=0;wire ok;wire[31:0] rd;
 ffc_raw10 #(.WIDTH(W),.HEIGHT(H),.STATS_FRAMES(FRAMES)) dut(
  .clk(clk),.resetn(resetn),.s_data(sd),.s_valid(sv),.s_sof(ss),.s_eol(se),
  .s_packet_error(sp),.s_global_fault(sf),.m_data(md),.m_valid(mv),.m_sof(ms),.m_eol(me),
  .m_packet_error(mp),.m_global_fault(mf),.csr_write(cw),.csr_read(cr),
  .csr_waddr(wa),.csr_raddr(ra),.csr_wdata(wd),.csr_write_ok(ok),.csr_rdata(rd));
 integer gx[0:N-1],gd[0:N-1];integer gold_enable=0,ped=52;
 integer mx=0,my=0,checked=0;integer px,py,out0,out1;
 reg[24:0] q[0:5];integer j;
 function integer correct(input integer value,input integer xx,input integer yy);
 integer i,fx,fy,a,b,c,d,dark,gain,v;
 begin
  i=(yy/32)*C+xx/32;fx=xx%32;fy=yy%32;
  dark=(gd[i]*(32-fx)*(32-fy)+gd[i+1]*fx*(32-fy)+gd[i+C]*(32-fx)*fy+gd[i+C+1]*fx*fy+512)/1024;
  gain=(gx[i]*(32-fx)*(32-fy)+gx[i+1]*fx*(32-fy)+gx[i+C]*(32-fx)*fy+gx[i+C+1]*fx*fy+512)/1024;
  v=value>dark ? value-dark : 0;v=(v*gain+2048)/4096+ped;
  correct=v>1023 ? 1023 : v;
 end endfunction
 always @(posedge clk) begin
  if(!resetn) begin for(j=0;j<6;j=j+1)q[j]=0;mx=0;my=0;end
  else begin
   for(j=5;j>0;j=j-1)q[j]=q[j-1];
   px=ss?0:mx;py=ss?0:my;
   out0=gold_enable?correct(sd[9:0],px,py):sd[9:0];
   out1=gold_enable?correct(sd[19:10],px+1,py):sd[19:10];
   q[0]={sf,sp,se&&sv,ss&&sv,sv,out1[9:0],out0[9:0]};
   if(sv)begin if(se)begin mx=0;my=py==H-1?0:py+1;end else begin mx=px+2;my=py;end end
   #1;
   if({mf,mp,me,ms,mv}!==q[5][24:20] || (mv && md!==q[5][19:0]))
    $fatal(1,"scoreboard mismatch pair=%0d actual=%h expected=%h",checked,{mf,mp,me,ms,mv,md},q[5]);
   if(mv)checked=checked+1;
  end
 end
 task write_csr(input[15:0] a,input[31:0] v,input bit accepted);
 begin @(negedge clk);cw=1;wa=a;wd=v;#1;if(ok!==accepted)$fatal(1,"write validation %h value%h",a,v);
 @(negedge clk);cw=0;end endtask
 task read_csr(input[15:0] a,output[31:0] v);
 begin @(negedge clk);ra=a;cr=1;@(posedge clk);#1;v=rd;@(negedge clk);cr=0;end endtask
 reg[31:0] v;integer n,x,y,k,i;integer seed=32'hffc12345;integer a,b;
 task frame(input bit bubbles);
 begin
  for(y=0;y<H;y=y+1)for(x=0;x<W;x=x+2)begin
   if(bubbles && (($random(seed)&7)==0))begin @(negedge clk);sv=0;ss=0;se=0;end
   @(negedge clk);sv=1;ss=(x==0&&y==0);se=(x==W-2);
   a=(100+x/32+y/32);b=a;
   sd={b[9:0],a[9:0]};
  end
  @(negedge clk);sv=0;ss=0;se=0;
 end endtask
 initial begin
  for(i=0;i<N;i=i+1)begin gd[i]=0;gx[i]=4096;end
  repeat(5)@(negedge clk);resetn=1;
  frame(1); // reset bypass, no initialized table
  write_csr(16'h3008,3,0);write_csr(16'h4004,4096<<10,0);
  for(i=0;i<N;i=i+1)write_csr(16'h4000+4*i,4096<<10,1);
  write_csr(16'h3010,0,1);ped=0;
  write_csr(16'h3008,3,1);write_csr(16'h3010,52,0);
  gold_enable=1;frame(1);repeat(8)@(negedge clk);
  read_csr(16'h3014,v);if(v!=1)$fatal(1,"apply seq");
  // Nonuniform map exercises both interpolation axes and lanes.
  for(i=0;i<N;i=i+1)begin
   gx[i]=4096+(i%C)*97+(i/C)*73;gd[i]=20+(i%C)*3+(i/C)*2;
   write_csr(16'h4000+4*i,(gx[i]<<10)|gd[i],1);
  end
  write_csr(16'h3010,52,1);ped=52;
  write_csr(16'h3008,3,1);frame(1);repeat(8)@(negedge clk);
  // Saturation and underflow.
  for(i=0;i<N;i=i+1)begin gx[i]=16383;gd[i]=i%2?1023:0;write_csr(16'h4000+4*i,(gx[i]<<10)|gd[i],1);end
  write_csr(16'h3008,3,1);frame(0);repeat(8)@(negedge clk);
  write_csr(16'h3008,2,1);gold_enable=0;frame(0);
  write_csr(16'h3040,1,1);repeat(CELLS+5)@(negedge clk);
  for(n=0;n<FRAMES;n=n+1)frame(1);
  repeat(8)@(negedge clk);read_csr(16'h3044,v);if(v!=2)$fatal(1,"stats status %h",v);
  for(i=0;i<CELLS;i=i+1)begin
   read_csr(16'h6000+4*i,v);
   if(v!=(100+i%(C-1)+i/(C-1))*1024*FRAMES)$fatal(1,"cell%0d got%0d",i,v);
  end
  write_csr(16'h3040,1,1);repeat(CELLS+5)@(negedge clk);
  @(negedge clk);sv=1;ss=1;se=1;sd=0;
  @(negedge clk);sv=0;ss=0;se=0;
  repeat(8)@(negedge clk);read_csr(16'h3044,v);if(v!=4)$fatal(1,"bad frame accepted %h",v);
  if(W==64 && H==64) begin
   write_csr(16'h3040,1,1);repeat(CELLS+5)@(negedge clk);
   for(n=0;n<FRAMES;n=n+1)frame(1);
   repeat(8)@(negedge clk);read_csr(16'h3044,v);if(v!=2)$fatal(1,"stats did not recover");
   read_csr(16'h6000,v);if(v!=100*1024*FRAMES)$fatal(1,"recovery retained partial sums");
  end
  $display("FFC_PASS W=%0d H=%0d FRAMES=%0d checked=%0d seed=ffc12345",W,H,FRAMES,checked);$finish;
 end
 initial begin #2000000000;$fatal(1,"timeout");end
endmodule
