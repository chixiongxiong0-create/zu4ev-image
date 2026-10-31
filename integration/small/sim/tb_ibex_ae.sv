`timescale 1ns/1ps
module tb_ibex_ae;
 `include "vector_count.svh"
 logic clk=0,rst=0;
 always #5 clk=~clk;
 logic [31:0] aa=0,wa=0,wd=0;
 logic [3:0] ws=15;
 logic av=0,rr=0,wav=0,wv=0,br=0;
 wire ar,rv,war,wr,bv;
 wire [31:0] rd; wire [1:0] rp,bp;
 wire memory_done;
 ibex_small_mem_check baseline_memory(.done_o(memory_done));
 ibex_small_system #(.RomFile("ae.mem"),.RamPrimitive("ultra"),.EnableInputMailbox(1)) dut(
 .clk_i(clk),.rst_ni(rst),.irq_software_i(1'b0),.irq_timer_i(1'b0),.irq_external_i(1'b0),
 .irq_fast_i(15'b0),.irq_nm_i(1'b0),.debug_req_i(1'b0),
 .core_sleep_o(),.alert_minor_o(),.alert_major_internal_o(),.alert_major_bus_o(),
 .s_axi_araddr(aa),.s_axi_arprot(3'b0),.s_axi_arvalid(av),.s_axi_arready(ar),
 .s_axi_rvalid(rv),.s_axi_rready(rr),.s_axi_rdata(rd),.s_axi_rresp(rp),
 .s_axi_awaddr(wa),.s_axi_awprot(3'b0),.s_axi_awvalid(wav),.s_axi_awready(war),
 .s_axi_wdata(wd),.s_axi_wstrb(ws),.s_axi_wvalid(wv),.s_axi_wready(wr),
 .s_axi_bvalid(bv),.s_axi_bready(br),.s_axi_bresp(bp));
 logic [31:0] vectors[0:AE_CASES*23-1];
 task automatic put(input logic[31:0] addr,val,input logic[3:0] mask,input logic[1:0] resp,input bit data_first);
  @(negedge clk); wa=addr;wd=val;ws=mask;
  if(data_first) wv=1;else wav=1;
  do @(posedge clk); while(data_first ? !wr : !war);
  @(negedge clk); wv=0;wav=0;
  repeat(2) @(negedge clk);
  if(data_first) wav=1;else wv=1;
  do @(posedge clk); while(data_first ? !war : !wr);
  @(negedge clk);wv=0;wav=0;
  wait(bv);#1;if(bp!==resp) $fatal(1,"mailbox write addr=%h resp=%h",addr,bp);
  repeat(2) begin @(posedge clk);#1;if(!bv || bp!==resp) $fatal(1,"B backpressure");end
  @(negedge clk);br=1;@(negedge clk);br=0;
 endtask
 task automatic get(input logic[31:0] addr,output logic[31:0] value);
  @(negedge clk);aa=addr;av=1;
  do @(posedge clk); while(!ar);
  @(negedge clk);av=0;
  wait(rv);#1;if(rp!==0) $fatal(1,"mailbox read error");value=rd;
  @(posedge clk);#1;if(!rv || rd!==value) $fatal(1,"R backpressure");
  @(negedge clk);rr=1;@(negedge clk);rr=0;
 endtask
 logic[31:0] value,version;
 int polls;
 initial begin
  $readmemh("vectors.mem",vectors);
  repeat(5) @(negedge clk);rst=1;
  polls=0;value=0;
  while(value!==32'h41454942 && polls<2000) begin get(32'h0023f83c,value);polls++;end
  if(value!==32'h41454942) $fatal(1,"AE boot failed %h",value);
  put(32'h00200000,32'hdeadbeef,15,2,0);
  put(32'h0023f800,32'hdeadbeef,15,2,1);
  put(32'h0023f001,32'hdeadbeef,15,2,0);
  put(32'h0023f100,32'h11223344,15,0,0);
  put(32'h0023f100,32'haabbccdd,5,0,1);
  get(32'h0023f100,value);if(value!==32'h11bb33dd) $fatal(1,"mailbox byte enables");
  for(int c=0;c<AE_CASES;c++) begin
   version=2*(c+1);
   put(32'h0023f000,version|1,15,0,0);
   for(int j=1;j<=13;j++) put(32'h0023f000+4*j,vectors[c*23+j-1],15,0,j%2);
   // Odd input version must never publish the corresponding even response.
   get(32'h0023f800,value);if(value===version) $fatal(1,"consumed odd input");
   put(32'h0023f000,version,15,0,1);
   polls=0;value=0;
   while(value!==version && polls<20000) begin get(32'h0023f800,value);polls++;end
   if(value!==version) $fatal(1,"AE timeout case=%0d value=%h",c,value);
   get(32'h0023f804,value);if(value!==vectors[c*23]) $fatal(1,"case ID mismatch");
   for(int j=0;j<10;j++) begin
    get(32'h0023f808+4*j,value);
    if(value!==vectors[c*23+13+j]) $fatal(1,"AE case=%0d field=%0d actual=%h expected=%h",c,j,value,vectors[c*23+13+j]);
   end
   get(32'h0023f800,value);if(value!==version) $fatal(1,"output snapshot changed");
   if(c%100==0) $display("IBEX_AE_PROGRESS %0d/%0d",c,AE_CASES);
  end
  wait(memory_done);
  $display("IBEX_AE_PASS cases=%0d original_r5_policy state_and_proposal mailbox",AE_CASES);
  $finish;
 end
 initial begin #100000000;$fatal(1,"AE global timeout");end
endmodule
