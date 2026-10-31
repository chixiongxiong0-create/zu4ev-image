`timescale 1ns/1ps
module tb_sensor_model;
 reg clk=0,rst=0,start=0,read_op=0;reg [15:0] reg_addr='h3e01;reg [7:0] data='ha5;
 tri1 scl,sda;wire scl_low,sda_low,busy,done,nack,timeout;wire [7:0] result;
 always #5 clk=~clk;assign scl=scl_low?1'b0:1'bz;assign sda=sda_low?1'b0:1'bz;
 sc130_sensor_model sensor(.scl(scl),.sda(sda));
 ibex_sensor_i2c #(.TimeoutCycles(5000),.MinHalfPeriod(8)) dut(.clk_i(clk),.rst_ni(rst),.start_i(start),.read_i(read_op),
  .device_i(7'h30),.register_i(reg_addr),.half_period_i(16'd8),.wdata_i(data),.scl_i(scl),.sda_i(sda),
  .scl_low_o(scl_low),.sda_low_o(sda_low),.busy_o(busy),.done_o(done),.nack_o(nack),.timeout_o(timeout),.rdata_o(result));
 task transaction(input bit is_read);
  begin @(negedge clk);read_op=is_read;start=1;@(negedge clk);start=0;wait(done);#1;
   if(nack||timeout) $fatal(1,"I2C failure");end
 endtask
 initial begin repeat(5) @(negedge clk);rst=1;transaction(0);transaction(1);
  if(result!==8'ha5 || sensor.writes!=1 || sensor.reads!=1) $fatal(1,"sensor mismatch %h writes=%d reads=%d",result,sensor.writes,sensor.reads);
  $display("PASS sensor behavioral model write and readback");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
