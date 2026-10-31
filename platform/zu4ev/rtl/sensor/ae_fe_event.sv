`timescale 1ns/1ps
// FE and SOF are synchronous to the CSI video clock. A single outstanding
// interrupt is coalesced; the sequence counts every delivered FE notification.
// PG232 sticky ISR.FE may merge physical frames before its W1C service, and
// fe_time records the notification after AXI service/CDC, not packet arrival.
module ae_fe_event(
 input wire clk,resetn,fe_pulse,sof_pulse,ack_toggle,
 output reg irq,
 output reg [15:0] frame_seq,
 output reg [13:0] sof_seq,
 output reg [15:0] frame_gray,
 output reg [13:0] sof_gray,
 output reg [63:0] fe_time,sof_time
);
 reg [63:0] cycles;
 (* ASYNC_REG="TRUE" *) reg ack_meta,ack_sync;
 reg ack_seen;
 always @(posedge clk) begin
  if(!resetn) begin
   cycles<=0;ack_meta<=0;ack_sync<=0;ack_seen<=0;
   irq<=0;frame_seq<=0;sof_seq<=0;frame_gray<=0;sof_gray<=0;fe_time<=0;sof_time<=0;
  end else begin
   cycles<=cycles+1;
   ack_meta<=ack_toggle;ack_sync<=ack_meta;
   if(ack_sync!=ack_seen) begin ack_seen<=ack_sync;irq<=0;end
   if(sof_pulse) begin
    sof_seq<=sof_seq+1'b1;
    sof_gray<=((sof_seq+14'd1) ^ ((sof_seq+14'd1)>>1));
    sof_time<=cycles;
   end
   if(fe_pulse) begin
    frame_seq<=frame_seq+1;
    frame_gray<=((frame_seq+16'd1) ^ ((frame_seq+16'd1)>>1));
    fe_time<=cycles;
    irq<=1;
   end
  end
 end
endmodule
