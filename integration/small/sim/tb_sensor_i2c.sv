`timescale 1ns/1ps
module tb_sensor_i2c;
  reg clk=0, resetn=0, start=0, rd=0, slave_sda_low=0, slave_scl_low=0;
  always #5 clk=~clk;
  tri1 scl, sda;
  wire scl_low, sda_low, busy, done, nack, timeout;
  wire [7:0] rdata;
  assign scl = scl_low || slave_scl_low ? 1'b0 : 1'bz;
  assign sda = sda_low || slave_sda_low ? 1'b0 : 1'bz;
  ibex_sensor_i2c #(.TimeoutCycles(5000),.MinHalfPeriod(8)) dut (
    .clk_i(clk),.rst_ni(resetn),.start_i(start),.read_i(rd),
    .device_i(7'h30),.register_i(16'h3e01),.half_period_i(16'd8),
    .wdata_i(8'ha5),.scl_i(scl),.sda_i(sda),.scl_low_o(scl_low),
    .sda_low_o(sda_low),.busy_o(busy),.done_o(done),.nack_o(nack),
    .timeout_o(timeout),.rdata_o(rdata));

  task automatic begin_command(input bit is_read);
    @(negedge clk); rd=is_read; start=1;
    @(negedge clk); start=0;
  endtask
  task automatic start_condition;
    @(negedge sda); if(scl !== 1'b1) $fatal(1,"START without SCL high");
  endtask
  task automatic stop_condition;
    @(posedge sda); if(scl !== 1'b1) $fatal(1,"STOP without SCL high");
  endtask
  task automatic receive_byte(input [7:0] expected,input bit ack);
    reg [7:0] got;
    integer i;
    begin
      for(i=7;i>=0;i=i-1) begin @(posedge scl); got[i]=sda; @(negedge scl); end
      if(got !== expected) $fatal(1,"byte got %h expected %h",got,expected);
      slave_sda_low=ack;
      @(posedge scl); @(negedge scl); slave_sda_low=0;
    end
  endtask
  task automatic transmit_byte(input [7:0] data);
    integer i;
    begin
      for(i=7;i>=0;i=i-1) begin
        slave_sda_low=~data[i]; @(posedge scl); @(negedge scl);
      end
      slave_sda_low=0;
      @(posedge scl); if(sda !== 1'b1) $fatal(1,"master failed to NACK final byte");
      @(negedge scl);
    end
  endtask
  task automatic check_done(input bit expect_nack,input bit expect_timeout);
    begin
      wait(done); #1;
      if(nack !== expect_nack || timeout !== expect_timeout || busy)
        $fatal(1,"bad completion nack=%b timeout=%b busy=%b",nack,timeout,busy);
    end
  endtask
  initial begin
    repeat(4) @(negedge clk); resetn=1;
    fork
      begin begin_command(0); check_done(0,0); end
      begin start_condition(); receive_byte(8'h60,1); receive_byte(8'h3e,1);
        receive_byte(8'h01,1); receive_byte(8'ha5,1); stop_condition(); end
    join
    fork
      begin begin_command(1); check_done(0,0); if(rdata!==8'h5a) $fatal(1,"read data %h",rdata); end
      begin start_condition(); receive_byte(8'h60,1); receive_byte(8'h3e,1);
        receive_byte(8'h01,1); start_condition(); receive_byte(8'h61,1);
        transmit_byte(8'h5a); stop_condition(); end
    join
    fork
      begin begin_command(0); check_done(1,0); end
      begin start_condition(); receive_byte(8'h60,0); stop_condition(); end
    join
    fork
      begin begin_command(0); check_done(1,0); end
      begin start_condition(); receive_byte(8'h60,1); receive_byte(8'h3e,0); stop_condition(); end
    join
    fork
      begin begin_command(0); check_done(1,0); end
      begin start_condition(); receive_byte(8'h60,1); receive_byte(8'h3e,1);
        receive_byte(8'h01,0); stop_condition(); end
    join
    fork
      begin begin_command(0); check_done(1,0); end
      begin start_condition(); receive_byte(8'h60,1); receive_byte(8'h3e,1);
        receive_byte(8'h01,1); receive_byte(8'ha5,0); stop_condition(); end
    join
    fork
      begin begin_command(1); check_done(1,0); end
      begin start_condition(); receive_byte(8'h60,1); receive_byte(8'h3e,1);
        receive_byte(8'h01,1); start_condition(); receive_byte(8'h61,0); stop_condition(); end
    join
    fork
      begin begin_command(0); check_done(0,0); end
      begin start_condition(); receive_byte(8'h60,1); receive_byte(8'h3e,1);
        receive_byte(8'h01,1); receive_byte(8'ha5,1); stop_condition(); end
      begin wait(busy); @(negedge scl); slave_scl_low=1;
        repeat(40) @(negedge clk); slave_scl_low=0; end
    join
    slave_scl_low=1;
    begin_command(0); check_done(0,1);
    slave_scl_low=0; repeat(10) @(negedge clk);
    if(scl_low || sda_low || scl !== 1'b1 || sda !== 1'b1) $fatal(1,"timeout did not release bus");
    $display("PASS sensor I2C write repeated-start read NACK timeout bus release");
    $finish;
  end
  initial begin #2000000; $fatal(1,"test timeout"); end
endmodule
