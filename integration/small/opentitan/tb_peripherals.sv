`timescale 1ns/1ps
module tb;
logic clk=0; always #5 clk=~clk; logic rst=0,req=0,we=0; logic [31:0] addr=0,wdata=0; logic [3:0] be=15; wire gnt,rv,err,integ,alert,irq_t,irq_e,irq_u; wire [31:0] data,go,ge; wire scl,scle,sda,sdae,tx; logic target_sda_low=0, target_scl_low=0; wire bus_scl=(!scle || scl) && !target_scl_low; wire bus_sda=(!sdae || sda) && !target_sda_low;
ibex_opentitan_peripherals dut(.clk_i(clk),.rst_ni(rst),.req_i(req),.we_i(we),.addr_i(addr),.wdata_i(wdata),.be_i(be),.gnt_o(gnt),.rvalid_o(rv),.err_o(err),.rdata_o(data),.integrity_error_o(integ),.alert_o(alert),.irq_timer_o(irq_t),.irq_external_o(irq_e),.irq_uart_o(irq_u),.gpio_i(32'h12345678),.gpio_o(go),.gpio_oe_o(ge),.i2c_scl_i(bus_scl),.i2c_sda_i(bus_sda),.i2c_scl_o(scl),.i2c_scl_oe_o(scle),.i2c_sda_o(sda),.i2c_sda_oe_o(sdae),.uart_rx_i(1'b1),.uart_tx_o(tx));
task automatic access(input bit wr,input logic [31:0] a,input logic [31:0] d,output logic [31:0] v); integer n; begin
@(negedge clk); req=1; we=wr; addr=a; wdata=d; n=0; do begin @(posedge clk); n++; if(n>100) $fatal(1,"grant timeout %h",a); end while(!gnt); @(negedge clk); req=0; n=0; do begin @(posedge clk); n++; if(n>200) $fatal(1,"response timeout %h",a); end while(!rv); if(err || integ) $fatal(1,"error %h err=%b integ=%b",a,err,integ); v=data; @(negedge clk); end endtask
logic [31:0] v;
initial begin repeat(5) @(posedge clk); @(negedge clk); rst=1; repeat(5) @(posedge clk);
access(1,32'h40030014,32'ha55a1234,v); access(0,32'h40030014,0,v); if(v!==32'ha55a1234) $fatal(1,"gpio data %h",v);
access(1,32'h40030020,32'h0000ffff,v); if(ge!==32'h0000ffff || go!==32'ha55a1234) $fatal(1,"gpio outputs %h %h",go,ge);
access(0,32'h40030010,0,v); if(v!==32'h12345678) $fatal(1,"gpio input %h",v);
access(1,32'h40000118,20,v); access(1,32'h4000011c,0,v); access(1,32'h40000100,1,v); access(1,32'h40000004,1,v); repeat(30) @(posedge clk); repeat(5) @(posedge clk); if(!irq_t) $fatal(1,"timer irq");
access(1,32'h40020004,4,v); access(1,32'h40020008,4,v); repeat(5) @(posedge clk); if(!irq_u || irq_e) $fatal(1,"UART IRQ isolation uart=%b external=%b",irq_u,irq_e); access(1,32'h40020000,4,v); repeat(5) @(posedge clk); if(irq_u || irq_e) $fatal(1,"UART IRQ clear");
access(1,32'h40030004,1,v); access(1,32'h40030008,1,v); repeat(5) @(posedge clk); if(!irq_e || irq_u) $fatal(1,"GPIO IRQ isolation"); access(1,32'h40030000,1,v); repeat(5) @(posedge clk); if(irq_e || irq_u) $fatal(1,"GPIO IRQ clear");
access(1,32'h40010004,512,v); access(1,32'h40010008,512,v); repeat(5) @(posedge clk); if(!irq_e || irq_u) $fatal(1,"I2C IRQ isolation"); access(1,32'h40010000,512,v); repeat(5) @(posedge clk); if(irq_e || irq_u) $fatal(1,"I2C IRQ clear"); $display("PASS IRQ UART/I2C/GPIO isolation and clear");
access(1,32'h40020010,32'hffff0001,v);
fork
 begin : framecheck
  logic [9:0] expected; expected=10'b1_01010101_0;
  @(negedge tx); repeat(8) @(posedge clk);
  for(int i=0;i<10;i++) begin if(tx !== expected[i]) $fatal(1,"UART bit %0d expected %b got %b",i,expected[i],tx); repeat(16) @(posedge clk); end
  if(!tx) $fatal(1,"UART stop"); $display("PASS UART 8N1 frame and 16-clock bit timing");
 end
 begin access(1,32'h4002001c,32'h55,v); end
join
access(1,32'h4001003c,32'h00050005,v); access(1,32'h40010040,32'h00030003,v); access(1,32'h40010044,32'h00030003,v); access(1,32'h40010048,32'h00030003,v); access(1,32'h4001004c,32'h00030003,v); access(1,32'h40010010,1,v);
fork
 begin : target_write
  logic [7:0] received;
  @(negedge bus_sda); // START
  for(int byte_no=0;byte_no<2;byte_no++) begin
   received=0;
   for(int bit_no=0;bit_no<8;bit_no++) begin @(posedge bus_scl); received={received[6:0],bus_sda}; @(negedge bus_scl); end
   if(received !== (byte_no==0 ? 8'ha0 : 8'h3c)) $fatal(1,"I2C write byte %0d = %h",byte_no,received);
   target_sda_low=1; @(posedge bus_scl); @(negedge bus_scl); target_sda_low=0;
  end
  $display("PASS I2C target ACK and write byte");
 end
 begin access(1,32'h4001001c,32'h000001a0,v); access(1,32'h4001001c,32'h0000023c,v); end
join
repeat(100) @(posedge clk);
access(0,32'h40010078,0,v); if(v != 0) $fatal(1,"unexpected I2C event %h",v);
fork
 begin : target_read
  logic [7:0] received; logic [7:0] reply;
  reply=8'h96; @(negedge bus_sda); received=0;
  for(int bit_no=0;bit_no<8;bit_no++) begin @(posedge bus_scl); received={received[6:0],bus_sda}; @(negedge bus_scl); end
  if(received !== 8'ha1) $fatal(1,"I2C read address %h",received);
  target_sda_low=1; @(posedge bus_scl); @(negedge bus_scl); target_sda_low=0;
  for(int bit_no=7;bit_no>=0;bit_no--) begin target_sda_low=!reply[bit_no]; @(posedge bus_scl); @(negedge bus_scl); end
  target_sda_low=0; @(posedge bus_scl); if(!bus_sda) $fatal(1,"controller should NACK final read byte"); @(negedge bus_scl);
 end
 begin access(1,32'h4001001c,32'h000001a1,v); access(1,32'h4001001c,32'h00000601,v); end
join
repeat(100) @(posedge clk); access(0,32'h40010018,0,v); if(v[7:0] !== 8'h96) $fatal(1,"I2C read data %h",v);
$display("PASS I2C target ACK and read byte");
// SC130-style transaction: address 0x30, 16-bit register 0x3e01,
// repeated START, two-byte read; target ACKs each address/register byte.
fork
 begin : sc130_register_read
  logic [7:0] received;
  logic [7:0] expected_byte;
  @(negedge bus_sda);
  for(int byte_no=0; byte_no<3; byte_no++) begin
   case (byte_no) 0: expected_byte=8'h60; 1: expected_byte=8'h3e; default: expected_byte=8'h01; endcase
   received=0;
   for(int bit_no=0; bit_no<8; bit_no++) begin @(posedge bus_scl); received={received[6:0],bus_sda}; @(negedge bus_scl); end
   if(received !== expected_byte) $fatal(1,"SC130 write byte %0d got %h expected %h",byte_no,received,expected_byte);
   target_sda_low=1; @(posedge bus_scl); @(negedge bus_scl); target_sda_low=0;
  end
  // START must occur while SCL is high, without an intervening STOP.
  @(posedge bus_scl); if(!bus_sda) $fatal(1,"SDA low before repeated start");
  @(negedge bus_sda); if(!bus_scl) $fatal(1,"repeated START without SCL high");
  received=0;
  for(int bit_no=0; bit_no<8; bit_no++) begin @(posedge bus_scl); received={received[6:0],bus_sda}; @(negedge bus_scl); end
  if(received !== 8'h61) $fatal(1,"SC130 read address %h",received);
  target_sda_low=1; @(posedge bus_scl); @(negedge bus_scl); target_sda_low=0;
  for(int byte_no=0; byte_no<2; byte_no++) begin
   expected_byte=(byte_no==0) ? 8'h96 : 8'h35;
   for(int bit_no=7; bit_no>=0; bit_no--) begin target_sda_low=!expected_byte[bit_no]; @(posedge bus_scl); @(negedge bus_scl); end
   target_sda_low=0; @(posedge bus_scl);
   if(bus_sda !== (byte_no==1)) $fatal(1,"SC130 read ACK/NACK byte %0d",byte_no);
   @(negedge bus_scl);
  end
  @(posedge bus_scl); @(posedge bus_sda); if(!bus_scl) $fatal(1,"STOP without SCL high");
 end
 begin
  access(1,32'h4001001c,32'h00000160,v);
  access(1,32'h4001001c,32'h0000003e,v);
  access(1,32'h4001001c,32'h00000001,v);
  access(1,32'h4001001c,32'h00000161,v);
  access(1,32'h4001001c,32'h00000602,v);
 end
join
repeat(100) @(posedge clk);
access(0,32'h40010018,0,v); if(v[7:0] !== 8'h96) $fatal(1,"SC130 first read %h",v);
access(0,32'h40010018,0,v); if(v[7:0] !== 8'h35) $fatal(1,"SC130 second read %h",v);
access(0,32'h40010078,0,v); if(v != 0) $fatal(1,"SC130 controller event %h",v);
$display("PASS I2C SC130 repeated-start 16-bit register two-byte read");
fork
 begin : sc130_register_write
  logic [7:0] received, expected_byte;
  @(negedge bus_sda);
  for(int byte_no=0; byte_no<4; byte_no++) begin
   case (byte_no) 0: expected_byte=8'h60; 1: expected_byte=8'h3e; 2: expected_byte=8'h01; default: expected_byte=8'h12; endcase
   received=0;
   for(int bit_no=0; bit_no<8; bit_no++) begin @(posedge bus_scl); received={received[6:0],bus_sda}; @(negedge bus_scl); end
   if(received !== expected_byte) $fatal(1,"SC130 register write byte %0d got %h expected %h",byte_no,received,expected_byte);
   target_sda_low=1; @(posedge bus_scl); @(negedge bus_scl); target_sda_low=0;
  end
  @(posedge bus_scl); @(posedge bus_sda); if(!bus_scl) $fatal(1,"SC130 write STOP without SCL high");
 end
 begin
  access(1,32'h4001001c,32'h00000160,v);
  access(1,32'h4001001c,32'h0000003e,v);
  access(1,32'h4001001c,32'h00000001,v);
  access(1,32'h4001001c,32'h00000212,v);
 end
join
repeat(100) @(posedge clk);
access(0,32'h40010078,0,v); if(v != 0) $fatal(1,"SC130 write controller event %h",v);
$display("PASS I2C SC130 16-bit register write");
// A target holds SCL low throughout a new transfer, causing controller bus timeout.
access(1,32'h40010050,32'hc0000010,v); target_scl_low=1;
access(1,32'h4001001c,32'h000003a0,v); repeat(250) @(posedge clk);
access(0,32'h40010078,0,v); if(!(v & 4)) $fatal(1,"I2C expected bus timeout %h",v); target_scl_low=0;
$display("PASS I2C bus timeout");
$display("PASS peripheral register GPIO timer and UART IRQ"); $finish; end
initial begin #100000; $fatal(1,"global timeout"); end
endmodule



