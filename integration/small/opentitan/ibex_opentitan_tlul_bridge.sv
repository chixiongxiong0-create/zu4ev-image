// SPDX-License-Identifier: Apache-2.0
// Single-outstanding native Ibex data-port bridge using genuine OpenTitan TL-UL.
module ibex_opentitan_tlul_bridge (
  input logic clk_i,
  input logic rst_ni,
  input logic req_i,
  output logic gnt_o,
  input logic we_i,
  input logic [31:0] addr_i,
  input logic [31:0] wdata_i,
  input logic [3:0] be_i,
  output logic rvalid_o,
  output logic [31:0] rdata_o,
  output logic err_o,
  output logic integrity_error_o,
  output tlul_pkg::tl_h2d_t tl_o,
  input tlul_pkg::tl_d2h_t tl_i
);
  logic busy_q;
  logic adapter_gnt;
  logic adapter_req;
  assign adapter_req = req_i && !busy_q;
  assign gnt_o = adapter_req && adapter_gnt;
  // No new request is accepted while a response is pending. The response has
  // priority for same-cycle acceptance/completion, including zero-latency slaves.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) busy_q <= 1'b0;
    else if (rvalid_o) busy_q <= 1'b0;
    else if (gnt_o) busy_q <= 1'b1;
  end
  tlul_adapter_host #(
    .MAX_REQS(1),
    .EnableDataIntgGen(1'b1),
    .EnableRspDataIntgCheck(1'b1)
  ) u_adapter (
    .clk_i,
    .rst_ni,
    .req_i(adapter_req),
    .gnt_o(adapter_gnt),
    .addr_i,
    .we_i,
    .wdata_i,
    .wdata_intg_i('0),
    .be_i,
    .instr_type_i(prim_mubi_pkg::MuBi4False),
    .user_rsvd_i('0),
    .valid_o(rvalid_o),
    .rdata_o,
    .rdata_intg_o(),
    .err_o,
    .intg_err_o(integrity_error_o),
    .tl_o,
    .tl_i
  );
endmodule
