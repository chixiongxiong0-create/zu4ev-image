// SPDX-License-Identifier: Apache-2.0
module ibex_isp_cfg_owner #(parameter bit EnableSensorOwnership=1'b0) (
 input wire [31:0] sensor_status_async_i,
 output wire owner_o,run_o,stop_o,
 input wire clk_i,rst_ni,
 input wire [15:0] ps_axi_awaddr,
 input wire ps_axi_awvalid,
 output wire ps_axi_awready,
 input wire [31:0] ps_axi_wdata,
 input wire [3:0] ps_axi_wstrb,
 input wire ps_axi_wvalid,
 output wire ps_axi_wready,
 output wire [1:0] ps_axi_bresp,
 output wire ps_axi_bvalid,
 input wire ps_axi_bready,
 input wire [15:0] ps_axi_araddr,
 input wire ps_axi_arvalid,
 output wire ps_axi_arready,
 output wire [31:0] ps_axi_rdata,
 output wire [1:0] ps_axi_rresp,
 output wire ps_axi_rvalid,
 input wire ps_axi_rready,
 input wire [15:0] cpu_axi_awaddr,
 input wire cpu_axi_awvalid,
 output wire cpu_axi_awready,
 input wire [31:0] cpu_axi_wdata,
 input wire [3:0] cpu_axi_wstrb,
 input wire cpu_axi_wvalid,
 output wire cpu_axi_wready,
 output wire [1:0] cpu_axi_bresp,
 output wire cpu_axi_bvalid,
 input wire cpu_axi_bready,
 input wire [15:0] cpu_axi_araddr,
 input wire cpu_axi_arvalid,
 output wire cpu_axi_arready,
 output wire [31:0] cpu_axi_rdata,
 output wire [1:0] cpu_axi_rresp,
 output wire cpu_axi_rvalid,
 input wire cpu_axi_rready,
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
 typedef enum logic [2:0] {ST_IDLE,ST_WRITE,ST_B,ST_READ,ST_R} state_t;
 state_t state_q,state_d;
 logic owner_q,client_q,run_q,stop_q,stop_pending_q;
 (* ASYNC_REG="TRUE" *) logic [31:0] sensor_status_meta_q,sensor_status_sync_q;
 assign owner_o=owner_q;
 assign run_o=run_q;
 assign stop_o=stop_q;
 always_ff @(posedge clk_i or negedge rst_ni)
  if(!rst_ni) begin sensor_status_meta_q<=0;sensor_status_sync_q<=0;end
  else begin sensor_status_meta_q<=sensor_status_async_i;sensor_status_sync_q<=sensor_status_meta_q;end
 logic [1:0] aw_full_q,w_full_q,ar_full_q,bvalid_q,rvalid_q;
 logic [15:0] aw_q[2],ar_q[2];
 logic [31:0] wd_q[2],rd_q[2];
 logic [3:0] ws_q[2];
 logic [1:0] br_q[2],rr_q[2];
 wire [1:0] awvalid,wvalid,arvalid,bready,rready;
 wire [15:0] awaddr[2],araddr[2];
 wire [31:0] wdata[2];
 wire [3:0] wstrb[2];
 wire [1:0] awready,wready,arready;
 logic pick_valid,pick_client,pick_write;
 wire [15:0] selected_address=pick_write ? aw_q[pick_client] : ar_q[pick_client];
 wire selected_owner=selected_address==16'hff00;
 wire selected_status=EnableSensorOwnership && selected_address==16'hff04;
 wire selected_run=EnableSensorOwnership && selected_address==16'hff08;
 wire selected_csr=selected_owner || selected_status || selected_run;
 wire selected_allowed = pick_client==owner_q;
 wire select_event = state_q==ST_IDLE && pick_valid;
 wire forward_event = select_event && !selected_csr && selected_allowed;
 wire local_event = select_event && !forward_event;
 wire local_write=local_event && pick_write;
 wire local_read=local_event && !pick_write;
 wire csr_bits_ok=((wd_q[0] &
    {{8{ws_q[0][3]}},{8{ws_q[0][2]}},{8{ws_q[0][1]}},{8{ws_q[0][0]}}} & 32'hfffffffe)==0);
 wire reclaim_safe=!EnableSensorOwnership || wd_q[0][0] || (!run_q && sensor_status_sync_q[0] && sensor_status_sync_q[9]==stop_q);
 wire stop_complete=sensor_status_sync_q[0] && sensor_status_sync_q[9]==stop_q;
 wire csr_write_ok=!pick_client && csr_bits_ok &&
   ((selected_owner && reclaim_safe) || (selected_run && (!wd_q[0][0] || (owner_q && !stop_pending_q))));
 logic aw_done_q,w_done_q;
 wire aw_fire=m_axi_awvalid && m_axi_awready;
 wire w_fire=m_axi_wvalid && m_axi_wready;
 wire b_fire=m_axi_bvalid && m_axi_bready;
 wire ar_fire=m_axi_arvalid && m_axi_arready;
 wire r_fire=m_axi_rvalid && m_axi_rready;
 assign awready={2{rst_ni}} & ~aw_full_q & ~bvalid_q;
 assign wready={2{rst_ni}} & ~w_full_q & ~bvalid_q;
 assign arready={2{rst_ni}} & ~ar_full_q & ~rvalid_q;
 assign m_axi_awaddr=aw_q[client_q];
 assign m_axi_wdata=wd_q[client_q];
 assign m_axi_wstrb=ws_q[client_q];
 assign m_axi_araddr=ar_q[client_q];
 assign m_axi_awvalid=state_q==ST_WRITE && !aw_done_q;
 assign m_axi_wvalid=state_q==ST_WRITE && !w_done_q;
 assign m_axi_bready=state_q==ST_B;
 assign m_axi_arvalid=state_q==ST_READ;
 assign m_axi_rready=state_q==ST_R;
 always_comb begin
  pick_valid=0;pick_client=0;pick_write=0;
  if(aw_full_q[0] && w_full_q[0] && !bvalid_q[0]) begin pick_valid=1;pick_write=1;end
  else if(ar_full_q[0] && !rvalid_q[0]) begin pick_valid=1;end
  else if(aw_full_q[1] && w_full_q[1] && !bvalid_q[1]) begin pick_valid=1;pick_client=1;pick_write=1;end
  else if(ar_full_q[1] && !rvalid_q[1]) begin pick_valid=1;pick_client=1;end
 end
 always_comb begin
  state_d=state_q;
  case(state_q)
   ST_IDLE: if(forward_event) state_d=pick_write ? ST_WRITE : ST_READ;
   ST_WRITE: if((aw_done_q||aw_fire) && (w_done_q||w_fire)) state_d=ST_B;
   ST_B: if(b_fire) state_d=ST_IDLE;
   ST_READ: if(ar_fire) state_d=ST_R;
   ST_R: if(r_fire) state_d=ST_IDLE;
   default: state_d=ST_IDLE;
  endcase
 end
 always_ff @(posedge clk_i or negedge rst_ni)
  if(!rst_ni) state_q<=ST_IDLE;else state_q<=state_d;
 always_ff @(posedge clk_i or negedge rst_ni) begin
  if(!rst_ni) begin
   owner_q<=0;run_q<=0;stop_q<=0;stop_pending_q<=0;client_q<=0;aw_done_q<=0;w_done_q<=0;
   aw_full_q<=0;w_full_q<=0;ar_full_q<=0;bvalid_q<=0;rvalid_q<=0;
   for(integer i=0;i<2;i=i+1) begin aw_q[i]<=0;ar_q[i]<=0;wd_q[i]<=0;ws_q[i]<=0;rd_q[i]<=0;br_q[i]<=0;rr_q[i]<=0;end
  end else begin
   if(stop_pending_q && stop_complete) stop_pending_q<=0;
   for(integer i=0;i<2;i=i+1) begin
    if(bvalid_q[i] && bready[i]) bvalid_q[i]<=0;
    if(rvalid_q[i] && rready[i]) rvalid_q[i]<=0;
    if(awvalid[i] && awready[i]) begin aw_q[i]<=awaddr[i];aw_full_q[i]<=1;end
    if(wvalid[i] && wready[i]) begin wd_q[i]<=wdata[i];ws_q[i]<=wstrb[i];w_full_q[i]<=1;end
    if(arvalid[i] && arready[i]) begin ar_q[i]<=araddr[i];ar_full_q[i]<=1;end
   end
   if(forward_event) begin client_q<=pick_client;aw_done_q<=0;w_done_q<=0;end
   if(aw_fire) aw_done_q<=1;
   if(w_fire) w_done_q<=1;
   if(local_write) begin
    aw_full_q[pick_client]<=0;w_full_q[pick_client]<=0;bvalid_q[pick_client]<=1;
    br_q[pick_client]<=csr_write_ok ? 2'b00 : 2'b10;
    if(csr_write_ok && ws_q[0][0]) begin
     if(selected_owner) owner_q<=wd_q[0][0];
     if(selected_run) begin
      run_q<=wd_q[0][0];
      if(!wd_q[0][0] && !stop_pending_q) begin
       stop_q<=~stop_q;stop_pending_q<=1;
      end
     end
    end
   end
   if(local_read) begin
    ar_full_q[pick_client]<=0;rvalid_q[pick_client]<=1;
    rr_q[pick_client]<=selected_csr ? 2'b00 : 2'b10;
    rd_q[pick_client]<=selected_owner ? {31'b0,owner_q} :
      selected_run ? {30'b0,stop_q,run_q} : selected_status ? sensor_status_sync_q : 32'b0;
   end
   if(b_fire) begin
    aw_full_q[client_q]<=0;w_full_q[client_q]<=0;
    bvalid_q[client_q]<=1;br_q[client_q]<=m_axi_bresp;
   end
   if(r_fire) begin
    ar_full_q[client_q]<=0;rvalid_q[client_q]<=1;
    rd_q[client_q]<=m_axi_rdata;rr_q[client_q]<=m_axi_rresp;
   end
  end
 end
 assign awaddr[0]=ps_axi_awaddr;
 assign awvalid[0]=ps_axi_awvalid;
 assign ps_axi_awready=awready[0];
 assign wdata[0]=ps_axi_wdata;
 assign wstrb[0]=ps_axi_wstrb;
 assign wvalid[0]=ps_axi_wvalid;
 assign ps_axi_wready=wready[0];
 assign ps_axi_bresp=br_q[0];
 assign ps_axi_bvalid=bvalid_q[0];
 assign bready[0]=ps_axi_bready;
 assign araddr[0]=ps_axi_araddr;
 assign arvalid[0]=ps_axi_arvalid;
 assign ps_axi_arready=arready[0];
 assign ps_axi_rdata=rd_q[0];
 assign ps_axi_rresp=rr_q[0];
 assign ps_axi_rvalid=rvalid_q[0];
 assign rready[0]=ps_axi_rready;
 assign awaddr[1]=cpu_axi_awaddr;
 assign awvalid[1]=cpu_axi_awvalid;
 assign cpu_axi_awready=awready[1];
 assign wdata[1]=cpu_axi_wdata;
 assign wstrb[1]=cpu_axi_wstrb;
 assign wvalid[1]=cpu_axi_wvalid;
 assign cpu_axi_wready=wready[1];
 assign cpu_axi_bresp=br_q[1];
 assign cpu_axi_bvalid=bvalid_q[1];
 assign bready[1]=cpu_axi_bready;
 assign araddr[1]=cpu_axi_araddr;
 assign arvalid[1]=cpu_axi_arvalid;
 assign cpu_axi_arready=arready[1];
 assign cpu_axi_rdata=rd_q[1];
 assign cpu_axi_rresp=rr_q[1];
 assign cpu_axi_rvalid=rvalid_q[1];
 assign rready[1]=cpu_axi_rready;
endmodule
