`timescale 1ns/1ps
// Reserved-memory destructive BIST. TEST_BYTES must be a positive multiple
// of 1024; TEST_BASE must be 1024-byte aligned and stay below 1GiB.
module tnr_ddr_bist #(
 parameter integer TEST_BYTES = 1048576,
 parameter [31:0] TEST_BASE = 32'h01000000
)(
 input wire clk, resetn, start, ready,
 output wire busy, output reg done, output reg [31:0] error_count,
 output wire [31:0] m_axi_awaddr, output wire [7:0] m_axi_awlen,
 output wire m_axi_awvalid, input wire m_axi_awready,
 output wire [127:0] m_axi_wdata, output wire [15:0] m_axi_wstrb,
 output wire m_axi_wlast, m_axi_wvalid, input wire m_axi_wready,
 input wire [1:0] m_axi_bresp, input wire m_axi_bvalid, output wire m_axi_bready,
 output wire [31:0] m_axi_araddr, output wire [7:0] m_axi_arlen,
 output wire m_axi_arvalid, input wire m_axi_arready,
 input wire [127:0] m_axi_rdata, input wire [1:0] m_axi_rresp,
 input wire m_axi_rlast, m_axi_rvalid, output wire m_axi_rready
);
 localparam [3:0] IDLE=0, WRITE_NEXT=1, WRITE_ADDR=2, WRITE_DATA=3,
 WRITE_RESP=4, READ_NEXT=5, READ_ADDR=6, READ_DATA=7;
 reg [3:0] state;
 reg [1:0] pattern;
 reg [31:0] offset;
 reg [6:0] beat;
 reg abort_run;
 reg [3:0] read_errors;
 integer lane;
 wire [31:0] burst_address=TEST_BASE+offset;
 wire [31:0] beat_address=burst_address+{21'b0,beat,4'b0};
 assign busy=(state!=IDLE);
 assign m_axi_awaddr=burst_address;
 assign m_axi_awlen=8'd63;
 assign m_axi_awvalid=(state==WRITE_ADDR);
 assign m_axi_wstrb=16'hffff;
 assign m_axi_wlast=(beat==63);
 assign m_axi_wvalid=(state==WRITE_DATA);
 assign m_axi_bready=(state==WRITE_RESP);
 assign m_axi_araddr=burst_address;
 assign m_axi_arlen=8'd63;
 assign m_axi_arvalid=(state==READ_ADDR);
 assign m_axi_rready=(state==READ_DATA);
 function automatic [31:0] expected_word(input [1:0] pat,input [31:0] address);
 begin
 case(pat)
 0: expected_word=32'b0;
 1: expected_word=32'hffffffff;
 default: expected_word=address^32'ha5a55a5a;
 endcase
 end
 endfunction
 genvar n;
 generate for(n=0;n<4;n=n+1) begin: DATA_PATTERN
 assign m_axi_wdata[n*32+:32]=expected_word(pattern,beat_address+n*4);
 end endgenerate
 always @* begin
 read_errors=0;
 for(lane=0;lane<4;lane=lane+1)
 if(m_axi_rdata[lane*32+:32]!=expected_word(pattern,beat_address+lane*4))
 read_errors=read_errors+1'b1;
 if(m_axi_rresp!=0) read_errors=read_errors+1'b1;
 if(m_axi_rlast!=(beat==63)) read_errors=read_errors+1'b1;
 end
 // Calibration loss latches an abort, without withdrawing any issued VALID.
 // Complete the outstanding burst/response, then finish with a nonzero count.
 // A nonresponding slave requires the coordinated fabric reset; no timeout
 // can legally discard an accepted AXI transaction.
 always @(posedge clk) begin
 if(!resetn) begin
 state<=IDLE; done<=0; error_count<=0; pattern<=0;
 offset<=0; beat<=0; abort_run<=0;
 end else begin
 if(busy && !ready) abort_run<=1;
 case(state)
 IDLE: if(start && ready) begin
 done<=0; error_count<=0; pattern<=0; offset<=0; beat<=0;
 abort_run<=0; state<=WRITE_NEXT;
 end
 WRITE_NEXT: begin
 if(abort_run || !ready) begin
 error_count<=error_count+1; done<=1; state<=IDLE;
 end else state<=WRITE_ADDR;
 end
 WRITE_ADDR: if(m_axi_awready) begin beat<=0; state<=WRITE_DATA; end
 WRITE_DATA: if(m_axi_wready) begin
 if(beat==63) state<=WRITE_RESP;
 else beat<=beat+1'b1;
 end
 WRITE_RESP: if(m_axi_bvalid) begin
 if(abort_run || !ready || m_axi_bresp!=0) begin
 error_count<=error_count+((m_axi_bresp!=0)?32'd1:32'd0)+((abort_run || !ready)?32'd1:32'd0);
 done<=1; state<=IDLE;
 end else if(offset==TEST_BYTES-1024) begin
 offset<=0; state<=READ_NEXT;
 end else begin offset<=offset+1024; state<=WRITE_NEXT; end
 end
 READ_NEXT: begin
 if(abort_run || !ready) begin
 error_count<=error_count+1; done<=1; state<=IDLE;
 end else state<=READ_ADDR;
 end
 READ_ADDR: if(m_axi_arready) begin beat<=0; state<=READ_DATA; end
 READ_DATA: if(m_axi_rvalid) begin
 error_count<=error_count+{28'b0,read_errors};
 if(m_axi_rlast) begin
 if(abort_run || !ready || beat!=63) begin
 error_count<=error_count+{28'b0,read_errors}+((abort_run || !ready)?32'd1:32'd0);
 done<=1; state<=IDLE;
 end else if(offset==TEST_BYTES-1024) begin
 if(pattern==2) begin done<=1; state<=IDLE; end
 else begin pattern<=pattern+1'b1; offset<=0; state<=WRITE_NEXT; end
 end else begin offset<=offset+1024; state<=READ_NEXT; end
 end else if(beat==63) begin
 // Missing LAST: keep accepting through eventual LAST, then abort.
 abort_run<=1; beat<=64;
 end else if(beat<64) beat<=beat+1'b1;
 end
 default: state<=IDLE;
 endcase
 end
 end
endmodule
