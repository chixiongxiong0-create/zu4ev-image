// SPDX-License-Identifier: Apache-2.0
// Read-only video snapshot. Payload is held from source acknowledgement until
// next request; two control synchronizers give payload a full settling interval.
module ibex_isp_snapshot (
 input logic clk_i,rst_ni,video_clk_i,video_rst_ni,
 input logic [511:0] stats_i,
 input logic [15:0] fe_seq_i,
 input logic [13:0] sof_seq_i,
 input logic req_i,we_i,
 input logic [31:0] addr_i,wdata_i,
 output logic gnt_o,rvalid_o,err_o,
 output logic [31:0] rdata_o,
 output logic irq_o
);
 (* ASYNC_REG="TRUE" *) logic [1:0] video_reset_sync;
 wire video_reset_n=video_reset_sync[1];
 always_ff @(posedge video_clk_i or negedge video_rst_ni)
  if(!video_rst_ni) video_reset_sync<=0;
  else video_reset_sync<={video_reset_sync[0],1'b1};
 logic request_q,ack_q,busy_q,we_q;
 logic [6:0] offset_q;
 logic [31:0] write_q;
 (* ASYNC_REG="TRUE" *) logic [1:0] request_sync,ack_sync;
 (* KEEP="TRUE", IBEX_CDC="PAYLOAD" *) logic [541:0] payload_q;
 (* KEEP="TRUE", IBEX_CDC="GRAY_SOURCE" *) logic [15:0] fe_gray;
 (* KEEP="TRUE", IBEX_CDC="GRAY_SOURCE" *) logic [15:0] sof_gray;
 always_ff @(posedge video_clk_i or negedge video_reset_n)
  if(!video_reset_n) begin fe_gray<=0;sof_gray<=0;end
  else begin fe_gray<=fe_seq_i^(fe_seq_i>>1);sof_gray<={2'b0,sof_seq_i^(sof_seq_i>>1)};end
 (* ASYNC_REG="TRUE", IBEX_CDC="GRAY_FIRST" *) logic [15:0] fe_meta,sof_meta;
 (* ASYNC_REG="TRUE" *) logic [15:0] fe_sync,sof_sync;
 function automatic [15:0] binary(input [15:0] gray);
  binary[15]=gray[15];
  for(integer i=14;i>=0;i=i-1) binary[i]=binary[i+1]^gray[i];
 endfunction
 logic [15:0] fe_observed_q,sof_observed_q;
 logic [15:0] fe_ack_q,sof_ack_q,fe_seen_q,sof_seen_q;
 assign gnt_o=req_i&&!busy_q&&!rvalid_o;
 assign irq_o=(fe_seen_q!=fe_ack_q)||(sof_seen_q!=sof_ack_q);
 always_ff @(posedge video_clk_i or negedge video_reset_n) begin
  if(!video_reset_n) begin request_sync<=0;ack_q<=0;payload_q<=0;end
  else begin
   request_sync<={request_sync[0],request_q};
   if(request_sync[1]!=ack_q) begin
    payload_q<={sof_seq_i,fe_seq_i,stats_i};
    ack_q<=request_sync[1];
   end
  end
 end
 always_ff @(posedge clk_i or negedge rst_ni) begin
  if(!rst_ni) begin
   request_q<=0;ack_sync<=0;busy_q<=0;rvalid_o<=0;
   err_o<=0;rdata_o<=0;we_q<=0;offset_q<=0;write_q<=0;
   fe_ack_q<=0;sof_ack_q<=0;fe_seen_q<=0;sof_seen_q<=0;
   fe_meta<=0;fe_sync<=0;sof_meta<=0;sof_sync<=0;fe_observed_q<=0;sof_observed_q<=0;
  end else begin
   ack_sync<={ack_sync[0],ack_q}; rvalid_o<=0;
   fe_meta<=fe_gray;fe_sync<=fe_meta;sof_meta<=sof_gray;sof_sync<=sof_meta;
   fe_seen_q<=binary(fe_sync);sof_seen_q<=binary(sof_sync);
   if(gnt_o) begin
    request_q<=!request_q;busy_q<=1;we_q<=we_i;
    offset_q<=addr_i[6:0];write_q<=wdata_i;
   end
   if(busy_q && ack_sync[1]==request_q) begin
    busy_q<=0;rvalid_o<=1;err_o<=0;rdata_o<=0;
    
    if(we_q) begin
     if(offset_q==7'h48) begin
      if(write_q[0]) fe_ack_q<=fe_observed_q;
      if(write_q[1]) sof_ack_q<=sof_observed_q;
     end else err_o<=1;
    end else if(offset_q<7'h40 && offset_q[1:0]==0)
     rdata_o<=payload_q[offset_q[5:2]*32+:32];
    else case(offset_q)
     7'h40:rdata_o<={16'b0,payload_q[527:512]};
     7'h44:rdata_o<={18'b0,payload_q[541:528]};
     7'h48:begin fe_observed_q<=fe_seen_q;sof_observed_q<=sof_seen_q;rdata_o<={30'b0,(sof_seen_q!=sof_ack_q),(fe_seen_q!=fe_ack_q)};end
     default:err_o<=1;
    endcase
   end
  end
 end
endmodule
