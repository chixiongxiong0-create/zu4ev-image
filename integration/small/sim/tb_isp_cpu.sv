`timescale 1ns/1ps
module tb_isp_cpu;
 reg clk=0,vc=0,cr=0,vr=0,valid=0,sof=0,eol=0,fe=0;
 always #5 clk=~clk; always #7 vc=~vc;
 wire [31:0] seq,frame,mean,count,bad,over,x,y,w,h; wire [47:0] sum;
 wire v,busy,active; wire [1:0] region; wire [9:0] black;
 ae_stats_raw10 #(.WIDTH(20),.HEIGHT(14)) source(.clk(vc),.resetn(vr),.s_data({10'd201,10'd101}),.s_valid(valid),.s_sof(sof),.s_eol(eol),.s_packet_error(1'b0),.s_global_fault(1'b0),.cfg_enable(1'b1),.cfg_region(2'd3),.cfg_black(10'd52),.result_valid(v),.div_busy(busy),.active_enable(active),.result_seq(seq),.result_frame(frame),.result_mean(mean),.result_count(count),.bad_frames(bad),.overruns(over),.result_sum(sum),.result_region(region),.result_black(black),.roi_x(x),.roi_y(y),.roi_width(w),.roi_height(h));
 wire [15:0] fseq,fg;wire [13:0] sseq,sg;wire ri;wire [63:0] ft,st;
 ae_fe_event ev(.clk(vc),.resetn(vr),.fe_pulse(fe),.sof_pulse(sof),.ack_toggle(1'b0),.irq(ri),.frame_seq(fseq),.sof_seq(sseq),.frame_gray(fg),.sof_gray(sg),.fe_time(ft),.sof_time(st));
 wire [511:0] stats={h,w,y,x,over,bad,{20'b0,black,region},{29'b0,active,busy,v},16'b0,sum,count,mean,frame,seq,64'b0};
 ibex_small_system #(.RomFile("isp_cpu.mem"),.EnableIspAccess(1)) dut(.clk_i(clk),.rst_ni(cr),.video_clk_i(vc),.video_rst_ni(vr),.isp_stats_i(stats),.isp_fe_seq_i(fseq),.isp_sof_seq_i(sseq),.irq_software_i(1'b0),.irq_timer_i(1'b0),.irq_external_i(1'b0),.irq_fast_i('0),.irq_nm_i(1'b0),.debug_req_i(1'b0),.s_axi_araddr('0),.s_axi_awaddr('0),.s_axi_wdata('0),.s_axi_arprot('0),.s_axi_awprot('0),.s_axi_wstrb('0),.s_axi_arvalid(1'b0),.s_axi_rready(1'b0),.s_axi_awvalid(1'b0),.s_axi_wvalid(1'b0),.s_axi_bready(1'b0),.loader_axi_araddr('0),.loader_axi_awaddr('0),.loader_axi_wdata('0),.loader_axi_arprot('0),.loader_axi_awprot('0),.loader_axi_wstrb('0),.loader_axi_arvalid(1'b0),.loader_axi_rready(1'b0),.loader_axi_awvalid(1'b0),.loader_axi_wvalid(1'b0),.loader_axi_bready(1'b0),.gpio_i('0),.i2c_scl_i(1'b1),.i2c_sda_i(1'b1),.uart_rx_i(1'b1));
 integer i;reg [31:0] got[0:3];reg irq_seen=0;
 always @(negedge clk) begin
 if(dut.u_core.irq_fast_i[1]) irq_seen=1;
 if(dut.data_gnt&&dut.data_we&&dut.data_addr>=32'h200000&&dut.data_addr<=32'h20000c) got[(dut.data_addr-32'h200000)/4]=dut.data_wdata;
 if(dut.data_gnt&&dut.data_we&&dut.data_addr==32'h200010) begin
 if(got[0]!==1||got[1]!==1||got[2]!==99||got[3]!==3||!irq_seen||!ri) $fatal(1,"CPU mismatch %d %d %d %d irq=%b r5=%b",got[0],got[1],got[2],got[3],irq_seen,ri);
 $display("PASS CPU real RAW10 stats FE SOF IRQ independent ACK");$finish;end end
 initial begin repeat(4) @(negedge vc);vr=1;for(i=0;i<140;i=i+1)begin @(negedge vc);valid=1;sof=i==0;eol=i%10==9;end @(negedge vc);valid=0;sof=0;eol=0;repeat(60) @(negedge vc);fe=1;@(negedge vc);fe=0;repeat(5) @(negedge clk);cr=1;end
 initial begin #500000;$fatal(1,"timeout pc=%h",dut.instr_addr);end
endmodule
