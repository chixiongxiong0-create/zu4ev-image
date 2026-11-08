`timescale 1ns/1ps
module tb_ffc_regs;
 reg clk=0;always #5 clk=~clk;
 reg resetn=0;reg[15:0] aw=0,ar=0;reg av=0,wv=0,br=0,rv=0,rr=0;
 reg[31:0] wd=0;reg[3:0] ws=15;
 wire aReady,wReady,bv,aRready,rvalid;wire[1:0] bp,rp;wire[31:0] rd;
 wire fw,fr,ok;wire[15:0] fwa,fra;wire[31:0] fwd,frd;
 reg sv=0,ss=0,se=0;reg[19:0] sd=0;
 isp_axi_regs #(.WIDTH(64),.HEIGHT(64),.FFC(1)) regs(
  .clk(clk),.resetn(resetn),.s_axi_awaddr(aw),.s_axi_awvalid(av),.s_axi_awready(aReady),
  .s_axi_wdata(wd),.s_axi_wstrb(ws),.s_axi_wvalid(wv),.s_axi_wready(wReady),
  .s_axi_bresp(bp),.s_axi_bvalid(bv),.s_axi_bready(br),
  .s_axi_araddr(ar),.s_axi_arvalid(rv),.s_axi_arready(aRready),
  .s_axi_rdata(rd),.s_axi_rresp(rp),.s_axi_rvalid(rvalid),.s_axi_rready(rr),
  .cfg_safe(1'b1),.frame_busy(1'b0),.frame_done(1'b0),.fault_count(32'd0),.fifo_level(13'd0),.curve_rdata(10'd0),
  .ffc_write(fw),.ffc_read(fr),.ffc_waddr(fwa),.ffc_raddr(fra),.ffc_wdata(fwd),.ffc_write_ok(ok),.ffc_rdata(frd));
 ffc_raw10 #(.WIDTH(64),.HEIGHT(64)) ffc(
 .clk(clk),.resetn(resetn),.s_data(sd),.s_valid(sv),.s_sof(ss),.s_eol(se),.s_packet_error(1'b0),.s_global_fault(1'b0),
 .csr_write(fw),.csr_read(fr),.csr_waddr(fwa),.csr_raddr(fra),.csr_wdata(fwd),.csr_write_ok(ok),.csr_rdata(frd));
 task write_bus(input[15:0] addr,input[31:0] value,input bit reverse,input[1:0] expected);
 begin
  if(reverse)begin
   @(negedge clk);wd=value;wv=1;do @(posedge clk);while(!wReady);@(negedge clk);wv=0;
   repeat(3)@(negedge clk);aw=addr;av=1;do @(posedge clk);while(!aReady);@(negedge clk);av=0;
  end else begin
   @(negedge clk);aw=addr;av=1;do @(posedge clk);while(!aReady);@(negedge clk);av=0;
   repeat(3)@(negedge clk);wd=value;wv=1;do @(posedge clk);while(!wReady);@(negedge clk);wv=0;
  end
  wait(bv);if(bp!==expected)$fatal(1,"BRESP %h got%h",addr,bp);
  repeat(4)begin @(negedge clk);if(!bv||bp!==expected)$fatal(1,"B hold");end
  br=1;@(negedge clk);br=0;
 end endtask
 task read_bus(input[15:0] addr,input[31:0] expected,input[1:0] response);
 begin
  @(negedge clk);ar=addr;rv=1;do @(posedge clk);while(!aRready);@(negedge clk);rv=0;
  wait(rvalid);#1;if(rd!==expected||rp!==response)$fatal(1,"R %h got%h expected%h resp%h",addr,rd,expected,rp);
  repeat(4)begin @(negedge clk);if(!rvalid||rd!==expected||rp!==response)$fatal(1,"R hold");end
  rr=1;@(negedge clk);rr=0;
 end endtask
 always @(posedge clk) if(resetn && fw && fr) $fatal(1,"shared RAM CPU port collision");
 integer i,x,y;
 initial begin
  repeat(4)@(negedge clk);resetn=1;
  read_bus(16'h3000,32'h46464331,0);read_bus(16'h0000,32'h49535031,0);
  fork
   write_bus(16'h3010,52,0,0);
   read_bus(16'h3000,32'h46464331,0);
  join
  write_bus(16'h3008,3,0,2);write_bus(16'h4004,4096<<10,1,2);
  for(i=0;i<9;i=i+1)write_bus(16'h4000+4*i,(4096<<10)|i,i%2,0);
  read_bus(16'h4000,(4096<<10),0);read_bus(16'h4020,(4096<<10)|8,0);
  read_bus(16'h3018,9,0);write_bus(16'h3008,3,1,0);
  write_bus(16'h3010,1,0,2);
  @(negedge clk);sv=1;ss=1;sd=0;
  @(negedge clk);sv=0;ss=0;
  read_bus(16'h300c,5,0);read_bus(16'h3014,1,0);
  write_bus(16'h3010,1024,1,2);read_bus(16'h3054,0,2);
  write_bus(16'h3040,1,1,0);repeat(12)@(negedge clk);
  for(i=0;i<32;i=i+1)for(y=0;y<64;y=y+1)for(x=0;x<64;x=x+2)begin
   @(negedge clk);sv=1;ss=(x==0&&y==0);se=x==62;sd={10'd55,10'd55};
  end
  @(negedge clk);sv=0;ss=0;se=0;
  read_bus(16'h3044,2,0);read_bus(16'h6000,55*1024*32,0);read_bus(16'h600c,55*1024*32,0);
  // Select the corrected stream with correction disabled; latency must not
  // change cell membership or the last sample of the final frame.
  write_bus(16'h3008,2,0,0);
  @(negedge clk);sv=1;ss=1;se=0;
  @(negedge clk);sv=0;ss=0;
  write_bus(16'h3050,1,1,0);read_bus(16'h3050,1,0);
  write_bus(16'h3040,1,0,0);repeat(12)@(negedge clk);
  for(i=0;i<32;i=i+1)for(y=0;y<64;y=y+1)for(x=0;x<64;x=x+2)begin
   @(negedge clk);sv=1;ss=(x==0&&y==0);se=x==62;sd={10'd55,10'd55};
  end
  @(negedge clk);sv=0;ss=0;se=0;repeat(8)@(negedge clk);
  read_bus(16'h3044,2,0);read_bus(16'h600c,55*1024*32,0);
  // Enabled FFC statistics must observe arithmetic output, not original RAW.
  for(i=0;i<9;i=i+1)write_bus(16'h4000+4*i,(4096<<10)|10,i%2,0);
  write_bus(16'h3008,3,0,0);
  @(negedge clk);sv=1;ss=1;se=0;
  @(negedge clk);sv=0;ss=0;
  write_bus(16'h3040,1,0,0);repeat(12)@(negedge clk);
  for(i=0;i<32;i=i+1)for(y=0;y<64;y=y+1)for(x=0;x<64;x=x+2)begin
   @(negedge clk);sv=1;ss=(x==0&&y==0);se=x==62;sd={10'd55,10'd55};
  end
  @(negedge clk);sv=0;ss=0;se=0;repeat(8)@(negedge clk);
  read_bus(16'h3044,2,0);read_bus(16'h6000,97*1024*32,0);read_bus(16'h600c,97*1024*32,0);
  // Reset cancels configuration and invalidates table progress.
  @(negedge clk);resetn=0;repeat(3)@(negedge clk);resetn=1;
  read_bus(16'h300c,0,0);read_bus(16'h3018,0,0);
  $display("FFC_AXI_PASS independent AW/W, stalled B/R, readback, stats, invalid access");$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
