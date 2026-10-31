`timescale 1ns/1ps
// Unthrottleable CSI tap with one-frame gate. The DMA and CPU register layer
// are deliberately separate; a complete result is not produced until dma_done.
module raw10_capture_tap #(
 parameter LINE_WORDS=640, FRAME_LINES=1024, FIFO_DEPTH=4096,
 parameter TIMEOUT_CYCLES=20000000
)(
 input wire clk,resetn,arm,abort_capture,ack,clear_stats,
 input wire [31:0] arm_epoch,ack_epoch,
 input wire [19:0] s_data,
 input wire s_valid,s_sof,s_eol,s_packet_error,s_global_fault,
 input wire dma_done,dma_error,
 output wire [31:0] m_data,
 output wire m_valid,m_sof,m_eol,input wire m_ready,
 output wire [31:0] status,output wire result_valid,
 output wire [31:0] result_epoch,result_flags,input_seq,result_seq,
 output wire [31:0] result_words,result_lines,dropped,overflows,complete
);
 wire [31:0] packed_data;
 wire packed_valid,packed_sof,packed_eol,packet_error,global_fault;
 raw10_u16_pack packer (
  .s_data(s_data),.s_valid(s_valid),.s_sof(s_sof),.s_eol(s_eol),
  .s_packet_error(s_packet_error),.s_global_fault(s_global_fault),
  .m_data(packed_data),.m_valid(packed_valid),.m_sof(packed_sof),
  .m_eol(packed_eol),.m_packet_error(packet_error),.m_global_fault(global_fault)
 );
 capture_frame_gate #(.LINE_WORDS(LINE_WORDS),.FRAME_LINES(FRAME_LINES),
  .FIFO_DEPTH(FIFO_DEPTH),.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) gate (
  .clk(clk),.resetn(resetn),.arm(arm),.abort_capture(abort_capture),
  .ack(ack),.clear_stats(clear_stats),.arm_epoch(arm_epoch),.ack_epoch(ack_epoch),
  .s_data(packed_data),.s_valid(packed_valid),.s_sof(packed_sof),.s_eol(packed_eol),
  .source_error(packet_error | global_fault),.dma_done(dma_done),.dma_error(dma_error),
  .m_data(m_data),.m_valid(m_valid),.m_sof(m_sof),.m_eol(m_eol),.m_ready(m_ready),
  .status(status),.result_valid(result_valid),.result_epoch(result_epoch),
  .result_flags(result_flags),.input_seq(input_seq),.result_seq(result_seq),
  .result_words(result_words),.result_lines(result_lines),.dropped(dropped),
  .overflows(overflows),.complete(complete)
 );
endmodule
