`timescale 1ns/1ps
module tb_isp_snapshot;
  reg cpu_clk=0, video_clk=0, rst=0, fe=0, sof=0, r5_ack=0;
  always #5 cpu_clk=~cpu_clk;
  always #7 video_clk=~video_clk;
  wire r5_irq; wire [15:0] fe_seq,fe_gray; wire [13:0] sof_seq,sof_gray;
  wire [63:0] fe_time,sof_time;
  ae_fe_event event_source(.clk(video_clk),.resetn(rst),.fe_pulse(fe),.sof_pulse(sof),
    .ack_toggle(r5_ack),.irq(r5_irq),.frame_seq(fe_seq),.sof_seq(sof_seq),
    .frame_gray(fe_gray),.sof_gray(sof_gray),.fe_time(fe_time),.sof_time(sof_time));
  reg [511:0] stats=0;
  reg req=0,we=0; reg [31:0] addr=0,wdata=0;
  wire gnt,rvalid,err,irq; wire [31:0] rdata;
  ibex_isp_snapshot dut(.clk_i(cpu_clk),.rst_ni(rst),.video_clk_i(video_clk),.video_rst_ni(rst),
    .stats_i(stats),.fe_seq_i(fe_seq),.sof_seq_i(sof_seq),
    .req_i(req),.we_i(we),.addr_i(addr),.wdata_i(wdata),
    .gnt_o(gnt),.rvalid_o(rvalid),.err_o(err),.rdata_o(rdata),.irq_o(irq));
  task access(input bit wr,input [31:0] a,input [31:0] d,input [31:0] expected,input bit bad);
    integer n; begin
      @(negedge cpu_clk); req=1;we=wr;addr=a;wdata=d;
      n=0; do begin @(posedge cpu_clk); #1; n=n+1; if(n>100) $fatal(1,"grant timeout"); end while(!dut.busy_q);
      @(negedge cpu_clk);req=0;
      n=0; while(!rvalid) begin @(posedge cpu_clk); #1; n=n+1; if(n>100) $fatal(1,"response timeout"); end
      if(err!==bad || (!wr && !bad && rdata!==expected)) $fatal(1,"access %h got %h err %b expected %h err %b",a,rdata,err,expected,bad);
    end
  endtask
  task pulse(input bit f,input bit s); begin
    @(negedge video_clk);fe=f;sof=s;@(negedge video_clk);fe=0;sof=0;
  end endtask
  integer i;
  initial begin
    repeat(4) @(negedge video_clk);rst=1;
    for(i=0;i<16;i=i+1) stats[i*32+:32]=32'h12340000+i;
    for(i=0;i<16;i=i+1) access(0,i*4,0,32'h12340000+i,0);
    access(0,'h48,0,0,0);
    pulse(1,1); repeat(4) @(posedge video_clk);
    if(!r5_irq) $fatal(1,"platform FE IRQ missing");
    access(0,'h40,0,1,0);access(0,'h44,0,1,0);access(0,'h48,0,3,0);
    if(!irq) $fatal(1,"Ibex pending missing");
    access(1,'h48,1,0,0);access(0,'h48,0,2,0);
    if(!r5_irq) $fatal(1,"Ibex FE ACK affected R5 IRQ");
    access(1,'h48,2,0,0);access(0,'h48,0,0,0);
    if(irq) $fatal(1,"pending did not clear");
    pulse(1,0);access(0,'h48,0,1,0);
    pulse(1,0);repeat(6) @(posedge cpu_clk);
    access(1,'h48,1,0,0);access(0,'h48,0,1,0);
    access(1,'h48,1,0,0);access(0,'h48,0,0,0);
    access(1,0,0,0,1);access(0,'h4c,0,0,1);
    @(negedge video_clk);rst=0;repeat(4) @(negedge video_clk);rst=1;
    access(0,'h40,0,0,0);access(0,'h44,0,0,0);access(0,'h48,0,0,0);
    $display("PASS ISP snapshot asynchronous clocks source event independent ACK reset");$finish;
  end
  initial begin #200000;$fatal(1,"watchdog");end
endmodule


