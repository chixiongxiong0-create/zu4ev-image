`timescale 1ns/1ps
module tb_sensor_ctrl;
  reg clk=0,rst=0,cpu_rst=0,owner=0,run=0,ps_scl=1,ps_sda=1;
  reg req=0,we=0; reg [31:0] addr=0,wdata=0; reg [3:0] be=15;
  reg slave_sda=0; tri1 scl,sda;
  wire scl_low,sda_low,grant,gnt,rvalid,err; wire [31:0] rdata,status;
  always #5 clk=~clk;
  assign scl = scl_low ? 1'b0 : 1'bz;
  assign sda = sda_low || slave_sda ? 1'b0 : 1'bz;
  ibex_sensor_ctrl #(.IdleCycles(500),.TimeoutCycles(5000),.MinHalfPeriod(8)) dut(
    .clk_i(clk),.rst_ni(rst),.cpu_rst_ni(cpu_rst),.owner_async_i(owner),.run_async_i(run),.stop_async_i(1'b0),
    .ps_scl_release_i(ps_scl),.ps_sda_release_i(ps_sda),.scl_i(scl),.sda_i(sda),
    .req_i(req),.we_i(we),.addr_i(addr),.wdata_i(wdata),.be_i(be),
    .gnt_o(gnt),.rvalid_o(rvalid),.err_o(err),.rdata_o(rdata),
    .scl_low_o(scl_low),.sda_low_o(sda_low),.grant_o(grant),.status_o(status));
  task automatic write_reg(input [7:0] a,input [31:0] d,input bit expect_error);
    begin
      @(negedge clk);addr=a;wdata=d;we=1;req=1;
      do @(posedge clk); while(!gnt);
      @(negedge clk);req=0;
      if(!rvalid || err!==expect_error) $fatal(1,"CSR %h error %b expected %b",a,err,expect_error);
    end
  endtask
  task automatic receive_byte(input [7:0] expected);
    integer i; reg [7:0] got;
    begin
      for(i=7;i>=0;i=i-1) begin @(posedge scl);got[i]=sda;@(negedge scl);end
      if(got!==expected) $fatal(1,"unexpected I2C byte %h expected %h",got,expected);
      slave_sda=1;@(posedge scl);@(negedge scl);slave_sda=0;
    end
  endtask
  initial begin
    repeat(4) @(negedge clk);rst=1;cpu_rst=1;
    ps_scl=0;owner=1;repeat(600) @(negedge clk);
    if(grant) $fatal(1,"granted while PS drives bus");
    ps_scl=1;repeat(400) @(negedge clk);
    if(grant) $fatal(1,"granted before 500 idle cycles");
    ps_sda=0;repeat(10) @(negedge clk);ps_sda=1;
    repeat(400) @(negedge clk);if(grant) $fatal(1,"idle timer failed to restart");
    wait(grant);write_reg('h1c,1,0);run=1;wait(status[3]);
    write_reg('h14,32'h3e01,0);write_reg('h18,32'ha5,0);
    fork
      begin
        write_reg('h10,32'h3001,0); wait(status[2]);
        repeat(20) @(negedge clk);cpu_rst=0;owner=0;
        repeat(10) @(negedge clk);
        if(!grant || !status[2] || status[0]) $fatal(1,"reset abandoned active transaction");
        wait(!status[2]); if(!grant) $fatal(1,"mux switched before bus idle");
        cpu_rst=1;run=0;wait(!grant);
      end
      begin
        @(negedge sda); if(scl!==1) $fatal(1,"invalid START");
        receive_byte(8'h60);receive_byte(8'h3e);receive_byte(8'h01);receive_byte(8'ha5);
        @(posedge sda);if(scl!==1) $fatal(1,"invalid STOP");
      end
    join
    write_reg('h10,32'h3001,1);
    owner=1;wait(grant);write_reg('h1c,1,0);run=1;wait(status[3]);
    run=0;repeat(4) @(negedge clk);write_reg('h1c,4,0);
    repeat(2) @(negedge clk);
    if(!status[0] || status[3]) $fatal(1,"quiesce failed");
    owner=0;wait(!grant);
    $display("PASS sensor ownership idle reset drain rearm quiesce");$finish;
  end
  initial begin #2000000;$fatal(1,"test timeout");end
endmodule
