`timescale 1ns/1ps
// Pack two decoded CSI MONO10 samples into two little-endian 16-bit words.
// Source is non-throttleable: the downstream capture gate must absorb every
// valid beat or invalidate the whole frame on overflow.
module raw10_u16_pack (
 input wire [19:0] s_data,
 input wire s_valid,s_sof,s_eol,s_packet_error,s_global_fault,
 output wire [31:0] m_data,
 output wire m_valid,m_sof,m_eol,m_packet_error,m_global_fault
);
 assign m_data = {6'b0,s_data[19:10],6'b0,s_data[9:0]};
 assign m_valid = s_valid;
 assign m_sof = s_sof;
 assign m_eol = s_eol;
 assign m_packet_error = s_packet_error;
 assign m_global_fault = s_global_fault;
endmodule
