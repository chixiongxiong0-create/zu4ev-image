// SPDX-License-Identifier: Apache-2.0
// Both clock domains must share reset assertion. Payload is held across toggles.
module ibex_isp_cfg_cdc (
 input wire clk_i, rst_ni, cfg_clk_i, cfg_rst_ni,
 input wire req_i, we_i, input wire [31:0] addr_i,wdata_i,
 input wire [3:0] be_i,
 output wire gnt_o, output logic rvalid_o,err_o,
 output logic [31:0] rdata_o,
 output wire req_o,we_o, output wire [31:0] addr_o,wdata_o,
 output wire [3:0] be_o,
 input wire gnt_i,rvalid_i,err_i,input wire [31:0] rdata_i
);
 wire common_reset_n = rst_ni && cfg_rst_ni;
 (* ASYNC_REG="TRUE" *) logic [1:0] src_reset_q,dst_reset_q;
 wire src_reset_n=src_reset_q[1],dst_reset_n=dst_reset_q[1];
 always_ff @(posedge clk_i or negedge common_reset_n)
  if(!common_reset_n) src_reset_q<=0; else src_reset_q<={src_reset_q[0],1'b1};
 always_ff @(posedge cfg_clk_i or negedge common_reset_n)
  if(!common_reset_n) dst_reset_q<=0; else dst_reset_q<={dst_reset_q[0],1'b1};
 logic request_q,ack_q,busy_q,issued_q;
 (* ASYNC_REG="TRUE" *) logic [1:0] request_sync_q,ack_sync_q;
 (* KEEP="TRUE", IBEX_CDC="CFG_REQUEST" *) logic [68:0] request_payload_q;
 (* KEEP="TRUE", IBEX_CDC="CFG_RESPONSE" *) logic [32:0] response_payload_q;
 assign gnt_o=src_reset_n && !busy_q && !rvalid_o;
 wire accept=req_i && gnt_o;
 wire complete=busy_q && ack_sync_q[1]==request_q;
 assign req_o=dst_reset_n && request_sync_q[1]!=ack_q && !issued_q;
 assign {we_o,be_o,addr_o,wdata_o}=request_payload_q;
 always_ff @(posedge clk_i or negedge src_reset_n) begin
  if(!src_reset_n) begin
   request_q<=0;busy_q<=0;ack_sync_q<=0;request_payload_q<=0;
   rvalid_o<=0;err_o<=0;rdata_o<=0;
  end else begin
   ack_sync_q<={ack_sync_q[0],ack_q};rvalid_o<=0;
   if(accept) begin request_payload_q<={we_i,be_i,addr_i,wdata_i};request_q<=!request_q;busy_q<=1;end
   if(complete) begin busy_q<=0;rvalid_o<=1;{err_o,rdata_o}<=response_payload_q;end
  end
 end
 always_ff @(posedge cfg_clk_i or negedge dst_reset_n) begin
  if(!dst_reset_n) begin request_sync_q<=0;ack_q<=0;issued_q<=0;response_payload_q<=0;end
  else begin
   request_sync_q<={request_sync_q[0],request_q};
   if(req_o && gnt_i) issued_q<=1;
   if(issued_q && rvalid_i) begin
    response_payload_q<={err_i,rdata_i};ack_q<=request_sync_q[1];issued_q<=0;
   end
  end
 end
endmodule
