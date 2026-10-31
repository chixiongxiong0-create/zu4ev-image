// SPDX-License-Identifier: Apache-2.0
// Single-clock PS loader. Memory accepts every load_req_o pulse and returns
// synchronous read data in the following cycle. Control bit 0 releases CPU reset.
// Firmware persists across reset; software must finish readback before setting RUN.
module ibex_small_loader #(
  parameter logic [31:0] FirmwareBase = 32'h00100000,
  parameter logic [31:0] FirmwareBytes = 32'h00040000
) (
  input logic clk_i, rst_ni,
  output logic cpu_rst_no,
  output logic load_req_o, load_we_o,
  output logic [31:0] load_addr_o, load_wdata_o,
  output logic [3:0] load_be_o,
  input logic [31:0] load_rdata_i,
  input logic [31:0] s_axi_araddr, s_axi_awaddr, s_axi_wdata,
  input logic [2:0] s_axi_arprot, s_axi_awprot,
  input logic [3:0] s_axi_wstrb,
  input logic s_axi_arvalid, s_axi_rready, s_axi_awvalid, s_axi_wvalid, s_axi_bready,
  output logic s_axi_arready, s_axi_rvalid, s_axi_awready, s_axi_wready, s_axi_bvalid,
  output logic [31:0] s_axi_rdata,
  output logic [1:0] s_axi_rresp, s_axi_bresp
);
  // Architecture: independently buffered AW/W join at write_exec. Writes have
  // priority over AR and are blocked during synchronous read capture. R/B payloads
  // remain registered until accepted. RUN and all protocol storage reset only
  // from rst_ni; CPU reset does not reset the loader. No additional FSM is needed.
  logic run_q, aw_seen_q, w_seen_q, read_pending_q;
  logic [31:0] awaddr_q, wdata_q;
  logic [3:0] wstrb_q;
  wire write_exec = aw_seen_q && w_seen_q && !s_axi_bvalid && !read_pending_q && !s_axi_rvalid;
  wire write_control = awaddr_q == 32'b0 && wstrb_q == 4'hf && wdata_q[31:1] == 0;
  wire write_memory = awaddr_q >= FirmwareBase &&
      (awaddr_q - FirmwareBase) < FirmwareBytes && awaddr_q[1:0] == 0;
  wire write_legal = write_control || (write_memory && !run_q);
  wire read_control = s_axi_araddr == 32'b0;
  wire read_memory = s_axi_araddr >= FirmwareBase &&
      (s_axi_araddr - FirmwareBase) < FirmwareBytes && s_axi_araddr[1:0] == 0;
  wire read_legal = read_control || (read_memory && !run_q);
  wire read_accept = s_axi_arvalid && s_axi_arready;

  assign cpu_rst_no = rst_ni && run_q;
  assign s_axi_awready = rst_ni && !aw_seen_q && !s_axi_bvalid;
  assign s_axi_wready = rst_ni && !w_seen_q && !s_axi_bvalid;
  assign s_axi_arready = rst_ni && !s_axi_rvalid && !read_pending_q && !write_exec;
  assign load_we_o = rst_ni && write_exec && write_memory && !run_q;
  assign load_req_o = load_we_o || (read_accept && read_memory && !run_q);
  assign load_addr_o = load_we_o ? awaddr_q : s_axi_araddr;
  assign load_wdata_o = wdata_q;
  assign load_be_o = load_we_o ? wstrb_q : 4'b0;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      run_q <= 1'b0;
      aw_seen_q <= 1'b0;
      w_seen_q <= 1'b0;
      awaddr_q <= 0;
      wdata_q <= 0;
      wstrb_q <= 0;
      s_axi_bvalid <= 1'b0;
      s_axi_bresp <= 0;
    end else begin
      if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;
      if (s_axi_awvalid && s_axi_awready) begin
        aw_seen_q <= 1'b1;
        awaddr_q <= s_axi_awaddr;
      end
      if (s_axi_wvalid && s_axi_wready) begin
        w_seen_q <= 1'b1;
        wdata_q <= s_axi_wdata;
        wstrb_q <= s_axi_wstrb;
      end
      if (write_exec) begin
        aw_seen_q <= 1'b0;
        w_seen_q <= 1'b0;
        s_axi_bvalid <= 1'b1;
        s_axi_bresp <= write_legal ? 2'b00 : 2'b10;
        if (write_control && wstrb_q[0]) run_q <= wdata_q[0];
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      read_pending_q <= 1'b0;
      s_axi_rvalid <= 1'b0;
      s_axi_rdata <= 0;
      s_axi_rresp <= 0;
    end else begin
      if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;
      read_pending_q <= 1'b0;
      if (read_accept) begin
        s_axi_rresp <= read_legal ? 2'b00 : 2'b10;
        if (read_memory && !run_q) begin
          read_pending_q <= 1'b1;
        end else begin
          s_axi_rvalid <= 1'b1;
          s_axi_rdata <= read_control ? {31'b0, run_q} : 32'b0;
        end
      end
      if (read_pending_q) begin
        s_axi_rvalid <= 1'b1;
        s_axi_rdata <= load_rdata_i;
      end
    end
  end
  // AXI protection attributes do not change access policy.
  wire unused_prot = ^{s_axi_arprot, s_axi_awprot};
endmodule

