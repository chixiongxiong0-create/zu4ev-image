`timescale 1ns/1ps
module tb_uart_irq;
logic clk=0,rst=0; always #5 clk=~clk;
ibex_small_system #(.RomFile("uart_irq.mem"),.EnablePeripherals(1)) dut (
.clk_i(clk),.rst_ni(rst),.irq_software_i(1'b0),.irq_timer_i(1'b0),.irq_external_i(1'b0),.irq_fast_i('0),.irq_nm_i(1'b0),.debug_req_i(1'b0),
.s_axi_araddr('0),.s_axi_awaddr('0),.s_axi_wdata('0),.s_axi_arprot('0),.s_axi_awprot('0),.s_axi_wstrb('0),.s_axi_arvalid(1'b0),.s_axi_rready(1'b0),.s_axi_awvalid(1'b0),.s_axi_wvalid(1'b0),.s_axi_bready(1'b0),
.loader_axi_araddr('0),.loader_axi_awaddr('0),.loader_axi_wdata('0),.loader_axi_arprot('0),.loader_axi_awprot('0),.loader_axi_wstrb('0),.loader_axi_arvalid(1'b0),.loader_axi_rready(1'b0),.loader_axi_awvalid(1'b0),.loader_axi_wvalid(1'b0),.loader_axi_bready(1'b0),
.gpio_i('0),.i2c_scl_i(1'b1),.i2c_sda_i(1'b1),.uart_rx_i(1'b1));
bit saw_irq=0, saw_clear=0; int assertions=0; bit previous=0;
initial begin rst=1; #1; rst=0; repeat(5) @(negedge clk); rst=1; repeat(20000) begin @(negedge clk);
 if(dut.u_core.irq_fast_i[0]) begin saw_irq=1; if(dut.u_core.irq_external_i) $fatal(1,"UART asserted external IRQ"); if(!previous) assertions++; previous=1; end else begin if(saw_irq) saw_clear=1; previous=0; end
 if(dut.data_gnt && dut.data_we && dut.data_addr==32'h00200010) begin if(dut.data_wdata !== 32'h600d6010 || !saw_irq || !saw_clear || assertions!=1 || dut.u_core.irq_fast_i[0]) $fatal(1,"IRQ trap failed signature=%h seen=%b clear=%b assertions=%0d",dut.data_wdata,saw_irq,saw_clear,assertions); $display("PASS CPU UART IRQ mcause=80000010 cleared and mret"); $finish; end end $fatal(1,"CPU UART IRQ timeout pc=%h",dut.instr_addr); end
endmodule
