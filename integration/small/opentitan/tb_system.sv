`timescale 1ns/1ps
module tb_system;
logic clk=0,rst=0; logic [14:0] fast=0; always #5 clk=~clk; wire [31:0] go,ge;
ibex_small_system #(.RomFile("cpu_test.mem"),.EnablePeripherals(1)) dut (
.clk_i(clk),.rst_ni(rst),.irq_software_i(1'b0),.irq_timer_i(1'b0),.irq_external_i(1'b0),.irq_fast_i(fast),.irq_nm_i(1'b0),.debug_req_i(1'b0),
.s_axi_araddr('0),.s_axi_awaddr('0),.s_axi_wdata('0),.s_axi_arprot('0),.s_axi_awprot('0),.s_axi_wstrb('0),.s_axi_arvalid(1'b0),.s_axi_rready(1'b0),.s_axi_awvalid(1'b0),.s_axi_wvalid(1'b0),.s_axi_bready(1'b0),
.loader_axi_araddr('0),.loader_axi_awaddr('0),.loader_axi_wdata('0),.loader_axi_arprot('0),.loader_axi_awprot('0),.loader_axi_wstrb('0),.loader_axi_arvalid(1'b0),.loader_axi_rready(1'b0),.loader_axi_awvalid(1'b0),.loader_axi_wvalid(1'b0),.loader_axi_bready(1'b0),
.gpio_i('0),.gpio_o(go),.gpio_oe_o(ge),.i2c_scl_i(1'b1),.i2c_sda_i(1'b1),.uart_rx_i(1'b1));
initial begin repeat(5) @(negedge clk); rst=1; fast=15'h4001; #1; if(dut.u_core.irq_fast_i !== 15'h4000) $fatal(1,"fast mux external bit0 not isolated"); fast=0; repeat(20000) begin @(negedge clk); if(dut.data_gnt && dut.data_we && dut.data_addr==32'h00200010) begin if(dut.data_wdata !== 32'h600d600d || go!==32'h5a3c || ge!==32'hff) $fatal(1,"CPU failure %h gpio %h %h",dut.data_wdata,go,ge); $display("PASS CPU memory and four peripheral windows"); $finish; end end $fatal(1,"CPU timeout pc=%h",dut.instr_addr); end
endmodule
