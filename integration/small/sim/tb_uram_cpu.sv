`timescale 1ns/1ps
module tb_uram_cpu;
  logic clk=0, rst_n=0;
  wire memory_done;
  assign memory_done = 1;
  always #5 clk=~clk;
  ibex_small_system #(.RomFile("selftest.mem"), .RamPrimitive("ultra"), .ProgramPrimitive("ultra"), .BootImageWords(65536)) dut (
    .clk_i(clk), .rst_ni(rst_n), .irq_software_i(1'b0), .irq_timer_i(1'b0),
    .irq_external_i(1'b0), .irq_fast_i(15'b0), .irq_nm_i(1'b0), .debug_req_i(1'b0),
    .s_axi_araddr(32'b0), .s_axi_awaddr(32'b0), .s_axi_wdata(32'b0),
    .s_axi_arprot(3'b0), .s_axi_awprot(3'b0), .s_axi_wstrb(4'b0),
    .s_axi_arvalid(1'b0), .s_axi_rready(1'b0), .s_axi_awvalid(1'b0),
    .s_axi_wvalid(1'b0), .s_axi_bready(1'b0), .core_sleep_o(), .alert_minor_o(), .alert_major_internal_o(), .alert_major_bus_o()
  );
  logic [31:0] signature;
  int reads=0, writes=0, errors=0;
  initial begin
    repeat (5) @(negedge clk);
    rst_n=1;
    wait(dut.memory_ready);
    repeat (20000) begin
      @(negedge clk);
      if (dut.data_gnt && dut.data_we) writes++;
      if (dut.data_gnt && !dut.data_we) reads++;
      if (dut.data_rvalid && dut.data_err) errors++;
      if (dut.data_gnt && dut.data_we && dut.data_addr==32'h00200010) begin
        if (dut.data_wdata !== 32'h600d600d) $fatal(1,"CPU failure signature %h stage=%h cause=%h",dut.data_wdata,32'b0,32'b0);
        if (errors!=2 || reads<5 || writes<5) $fatal(1,"Missing test activity");
        signature=dut.data_wdata;
        wait(memory_done);
        $display("IBEX_SMALL_PASS signature=%h reads=%0d writes=%0d errors=%0d",signature,reads,writes,errors);
        $finish;
      end
    end
    $fatal(1,"CPU timeout pc/address=%h",dut.instr_addr);
  end
endmodule
