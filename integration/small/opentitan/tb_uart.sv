`timescale 1ns/1ps
module tb_uart;
logic clk=0; always #5 clk=~clk; logic rst=0,req=0,we=0,rx=1; logic [31:0] addr=0,wdata=0; wire gnt,rv,err,integ,tx; wire [31:0] data;
ibex_opentitan_peripherals dut(.clk_i(clk),.rst_ni(rst),.req_i(req),.we_i(we),.addr_i(addr),.wdata_i(wdata),.be_i(4'hf),.gnt_o(gnt),.rvalid_o(rv),.err_o(err),.rdata_o(data),.integrity_error_o(integ),.gpio_i('0),.i2c_scl_i(1'b1),.i2c_sda_i(1'b1),.uart_rx_i(rx),.uart_tx_o(tx));
task automatic access(input bit wr,input logic [31:0] a,input logic [31:0] d,output logic [31:0] v); int n; begin @(negedge clk); req=1; we=wr; addr=a; wdata=d; n=0; do begin @(posedge clk); n++; if(n>100) $fatal(1,"grant timeout"); end while(!gnt); @(negedge clk); req=0; n=0; do begin @(posedge clk); n++; if(n>200) $fatal(1,"response timeout"); end while(!rv); if(err||integ) $fatal(1,"bus error"); v=data; @(negedge clk); end endtask
function automatic logic [7:0] pattern(input int i); case(i%4) 0:pattern=8'h00; 1:pattern=8'hff; 2:pattern=8'h55; 3:pattern=8'haa; endcase endfunction
task automatic tx_case(input int count); logic [31:0] v; logic [7:0] got; time last_start, delta; begin last_start=0;
 fork
  begin for(int i=0;i<count;i++) access(1,32'h4002001c,pattern(i),v); end
  begin for(int i=0;i<count;i++) begin @(negedge tx); if(i>0) begin delta=$time-last_start; if(delta<1600 || delta>1620) $fatal(1,"TX frame gap cycles: %0t",delta); end last_start=$time; repeat(8) @(posedge clk); if(tx!==0) $fatal(1,"TX start"); for(int b=0;b<8;b++) begin repeat(16) @(posedge clk); got[b]=tx; end repeat(16) @(posedge clk); if(!tx || got!==pattern(i)) $fatal(1,"TX byte %0d got %h expected %h",i,got,pattern(i)); repeat(8) @(posedge clk); end end
 join
 access(0,32'h40020014,0,v); if(!(v & 8)) $fatal(1,"TX not idle %h",v); $display("PASS UART TX length=%0d FIFO sequential frames",count);
 end endtask
task automatic tx_gaps; logic [31:0] v; logic [7:0] got; time start_at, previous, delta, write_at; begin previous=0;
 for(int i=0;i<4;i++) begin
  fork
   begin write_at=$time; access(1,32'h4002001c,pattern(i),v); end
   begin @(negedge tx); start_at=$time; if(i>0) begin delta=start_at-previous; if(start_at < write_at || start_at-write_at > 320 || delta < (160+(i==1?16:i==2?64:112))*10) $fatal(1,"TX timing start delta=%0t from write=%0t",delta,start_at-write_at); $display("TX gap %0d start-to-start=%0t write-to-start=%0t",i,delta,start_at-write_at); end previous=start_at;
    repeat(8) @(posedge clk); if(tx!==0) $fatal(1,"TX start"); for(int b=0;b<8;b++) begin repeat(16) @(posedge clk); got[b]=tx; end repeat(16) @(posedge clk); if(!tx || got!==pattern(i)) $fatal(1,"TX gapped byte %0d got %h",i,got); repeat(8) @(posedge clk); end
  join
  case(i) 0: repeat(16) @(posedge clk); 1: repeat(64) @(posedge clk); 2: repeat(112) @(posedge clk); endcase
 end
 $display("PASS UART TX measured varied gaps and byte order"); end endtask
task automatic rx_case(input int count,input int gap_mode); logic [31:0] v; int gap; begin
 for(int i=0;i<count;i++) begin
  @(negedge clk); rx=0; repeat(16) @(negedge clk);
  for(int b=0;b<8;b++) begin rx=(pattern(i) >> b) & 1; repeat(16) @(negedge clk); end
  rx=1; repeat(16) @(negedge clk); gap=(gap_mode==3)?(i%3==2?4:i%3):gap_mode; repeat(gap*16) @(negedge clk);
 end
 repeat(32) @(posedge clk); access(0,32'h40020024,0,v); if(v[23:16]!==count) $fatal(1,"RX level %h expected %0d",v,count);
 for(int i=0;i<count;i++) begin access(0,32'h40020018,0,v); if(v[7:0]!==pattern(i)) $fatal(1,"RX %0d=%h expected=%h",i,v[7:0],pattern(i)); end
 access(0,32'h40020000,0,v); if(v & 32'h18) $fatal(1,"RX overflow/frame error %h",v); access(0,32'h40020014,0,v); if(!(v & 32)) $fatal(1,"RX not empty %h",v); $display("PASS UART RX length=%0d gap_mode=%0d FIFO ordered",count,gap_mode);
 end endtask
logic [31:0] v;
initial begin repeat(5) @(posedge clk); @(negedge clk); rst=1; repeat(5) @(posedge clk); access(1,32'h40020010,32'hffff0003,v);
 tx_case(1); tx_case(2); tx_case(8); tx_case(24); tx_gaps();
 rx_case(1,0); rx_case(2,1); rx_case(8,4); rx_case(40,3);
 $display("PASS UART multi-byte matrix"); $finish; end
initial begin #2000000; $fatal(1,"UART global timeout"); end
endmodule

