// SPDX-License-Identifier: Apache-2.0
module ibex_native_to_axi_lite (
 input wire clk_i, rst_ni, req_i, we_i,
 input wire [31:0] addr_i, wdata_i,
 input wire [3:0] be_i,
 output wire gnt_o,
 output logic rvalid_o, err_o,
 output logic [31:0] rdata_o,
 output wire [15:0] m_axi_awaddr,
 output wire m_axi_awvalid,
 input wire m_axi_awready,
 output wire [31:0] m_axi_wdata,
 output wire [3:0] m_axi_wstrb,
 output wire m_axi_wvalid,
 input wire m_axi_wready,
 input wire [1:0] m_axi_bresp,
 input wire m_axi_bvalid,
 output wire m_axi_bready,
 output wire [15:0] m_axi_araddr,
 output wire m_axi_arvalid,
 input wire m_axi_arready,
 input wire [31:0] m_axi_rdata,
 input wire [1:0] m_axi_rresp,
 input wire m_axi_rvalid,
 output wire m_axi_rready
);
 (* ASYNC_REG="TRUE" *) logic [1:0] reset_sync_q;
 wire reset_n=reset_sync_q[1];
 always_ff @(posedge clk_i or negedge rst_ni)
  if(!rst_ni) reset_sync_q<=0;else reset_sync_q<={reset_sync_q[0],1'b1};
 typedef enum logic [2:0] {ST_IDLE, ST_WRITE, ST_B, ST_READ, ST_R} state_t;
 state_t state_q, state_d;
 logic [15:0] addr_q;
 logic [31:0] data_q;
 logic [3:0] be_q;
 logic aw_done_q, w_done_q;
 wire accept = req_i && gnt_o;
 wire aw_fire = m_axi_awvalid && m_axi_awready;
 wire w_fire = m_axi_wvalid && m_axi_wready;
 wire b_fire = m_axi_bvalid && m_axi_bready;
 wire ar_fire = m_axi_arvalid && m_axi_arready;
 wire r_fire = m_axi_rvalid && m_axi_rready;
 assign gnt_o = reset_n && state_q == ST_IDLE && !rvalid_o;
 assign m_axi_awaddr = addr_q;
 assign m_axi_wdata = data_q;
 assign m_axi_wstrb = be_q;
 assign m_axi_araddr = addr_q;
 assign m_axi_awvalid = state_q == ST_WRITE && !aw_done_q;
 assign m_axi_wvalid = state_q == ST_WRITE && !w_done_q;
 assign m_axi_bready = state_q == ST_B;
 assign m_axi_arvalid = state_q == ST_READ;
 assign m_axi_rready = state_q == ST_R;
 always_comb begin
  state_d = state_q;
  case(state_q)
   ST_IDLE: if(accept) state_d = we_i ? ST_WRITE : ST_READ;
   ST_WRITE: if((aw_done_q || aw_fire) && (w_done_q || w_fire)) state_d = ST_B;
   ST_B: if(b_fire) state_d = ST_IDLE;
   ST_READ: if(ar_fire) state_d = ST_R;
   ST_R: if(r_fire) state_d = ST_IDLE;
   default: state_d = ST_IDLE;
  endcase
 end
 always_ff @(posedge clk_i or negedge reset_n)
  if(!reset_n) state_q <= ST_IDLE;
  else state_q <= state_d;
 always_ff @(posedge clk_i or negedge reset_n) begin
  if(!reset_n) begin
   addr_q<=0; data_q<=0; be_q<=0; aw_done_q<=0; w_done_q<=0;
   rvalid_o<=0; err_o<=0; rdata_o<=0;
  end else begin
   rvalid_o<=0;
   if(accept) begin
    addr_q<=addr_i[15:0]; data_q<=wdata_i; be_q<=be_i;
    aw_done_q<=0; w_done_q<=0;
   end
   if(aw_fire) aw_done_q<=1;
   if(w_fire) w_done_q<=1;
   if(b_fire || r_fire) begin
    rvalid_o<=1;
    err_o<= b_fire ? (m_axi_bresp!=0) : (m_axi_rresp!=0);
    rdata_o<=r_fire ? m_axi_rdata : 32'b0;
   end
  end
 end
endmodule
