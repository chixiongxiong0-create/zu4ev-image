`timescale 1ns/1ps
module tb_board_validation;
reg clk=0, vc=0, rst=0, cr=0, cpu_rst=1, hold_aw=0; wire regs_awready; always #5 clk=~clk; always #7 vc=~vc;
reg [15:0] ps_awaddr=0,ps_araddr=0; reg [31:0] ps_wdata=0; reg [3:0] ps_wstrb=0;
reg ps_awvalid=0,ps_wvalid=0,ps_bready=0,ps_arvalid=0,ps_rready=0;
wire [15:0] cpu_awaddr;
wire cpu_awvalid;
wire cpu_awready;
wire [31:0] cpu_wdata;
wire [3:0] cpu_wstrb;
wire cpu_wvalid;
wire cpu_wready;
wire [1:0] cpu_bresp;
wire cpu_bvalid;
wire cpu_bready;
wire [15:0] cpu_araddr;
wire cpu_arvalid;
wire cpu_arready;
wire [31:0] cpu_rdata;
wire [1:0] cpu_rresp;
wire cpu_rvalid;
wire cpu_rready;
wire [15:0] m_awaddr;
wire m_awvalid;
wire m_awready; assign m_awready=regs_awready && !hold_aw;
wire [31:0] m_wdata;
wire [3:0] m_wstrb;
wire m_wvalid;
wire m_wready;
wire [1:0] m_bresp;
wire m_bvalid;
wire m_bready;
wire [15:0] m_araddr;
wire m_arvalid;
wire m_arready;
wire [31:0] m_rdata; wire [31:0] regs_rdata; reg inject_fault=0; reg [15:0] last_read=0;
assign m_rdata = (inject_fault && writes==4 && last_read==16'h14) ? (regs_rdata ^ 32'h1) : regs_rdata;
always @(posedge vc) if(m_arvalid && m_arready) last_read<=m_araddr;
wire [1:0] m_rresp;
wire m_rvalid;
wire m_rready;
wire ps_awready;
wire ps_wready;
wire [1:0] ps_bresp;
wire ps_bvalid;
wire ps_arready;
wire [31:0] ps_rdata;
wire [1:0] ps_rresp;
wire ps_rvalid;
wire [1:0] cfg_mode; wire [9:0] ae_black; wire cfg_pending;
reg valid=0,sof=0,eol=0,fe=0;
 wire [31:0] seq,frame,mean,count,bad,over,x,y,w,h; wire [47:0] sum;
 wire v,busy,active; wire [1:0] region; wire [9:0] black;
 ae_stats_raw10 #(.WIDTH(20),.HEIGHT(14)) source(.clk(vc),.resetn(rst),.s_data({10'd201,10'd101}),.s_valid(valid),.s_sof(sof),.s_eol(eol),.s_packet_error(1'b0),.s_global_fault(1'b0),.cfg_enable(1'b1),.cfg_region(2'd3),.cfg_black(10'd52),.result_valid(v),.div_busy(busy),.active_enable(active),.result_seq(seq),.result_frame(frame),.result_mean(mean),.result_count(count),.bad_frames(bad),.overruns(over),.result_sum(sum),.result_region(region),.result_black(black),.roi_x(x),.roi_y(y),.roi_width(w),.roi_height(h));
 wire [15:0] fseq,fg;wire [13:0] sseq,sg;wire ri;wire [63:0] ft,st;
 ae_fe_event ev(.clk(vc),.resetn(rst),.fe_pulse(fe),.sof_pulse(sof),.ack_toggle(1'b0),.irq(ri),.frame_seq(fseq),.sof_seq(sseq),.frame_gray(fg),.sof_gray(sg),.fe_time(ft),.sof_time(st));
 wire [511:0] stats={h,w,y,x,over,bad,{20'b0,black,region},{29'b0,active,busy,v},16'b0,sum,count,mean,frame,seq,64'b0};

reg [31:0] host_addr=0,host_data=0; reg host_aw=0,host_w=0,host_br=0; wire host_ar,host_wr,host_bv; wire [1:0] host_resp;
ibex_small_system #(.RomFile("board_validation.mem"),.EnableIspAccess(1),.EnableIspConfig(1),.EnableCpuResetInput(1),.EnableInputMailbox(1)) dut(
 .cpu_rst_ni(cpu_rst),.clk_i(clk),.rst_ni(cr),.video_clk_i(vc),.video_rst_ni(rst),.isp_cfg_clk_i(vc),.isp_cfg_rst_ni(rst),
 .isp_stats_i(stats),.isp_fe_seq_i(fseq),.isp_sof_seq_i(sseq),
 .irq_software_i(1'b0),.irq_timer_i(1'b0),.irq_external_i(1'b0),.irq_fast_i('0),.irq_nm_i(1'b0),.debug_req_i(1'b0),
 .s_axi_araddr('0),.s_axi_awaddr(host_addr),.s_axi_wdata(host_data),.s_axi_arprot('0),.s_axi_awprot('0),.s_axi_wstrb(4'hf),.s_axi_arvalid(1'b0),.s_axi_rready(1'b0),.s_axi_awvalid(host_aw),.s_axi_wvalid(host_w),.s_axi_bready(host_br),.s_axi_awready(host_ar),.s_axi_wready(host_wr),.s_axi_bvalid(host_bv),.s_axi_bresp(host_resp),
 .loader_axi_araddr('0),.loader_axi_awaddr('0),.loader_axi_wdata('0),.loader_axi_arprot('0),.loader_axi_awprot('0),.loader_axi_wstrb('0),.loader_axi_arvalid(1'b0),.loader_axi_rready(1'b0),.loader_axi_awvalid(1'b0),.loader_axi_wvalid(1'b0),.loader_axi_bready(1'b0),
 .gpio_i('0),.i2c_scl_i(1'b1),.i2c_sda_i(1'b1),.uart_rx_i(1'b1),
 .m_isp_axi_awaddr(cpu_awaddr),
 .m_isp_axi_awvalid(cpu_awvalid),
 .m_isp_axi_awready(cpu_awready),
 .m_isp_axi_wdata(cpu_wdata),
 .m_isp_axi_wstrb(cpu_wstrb),
 .m_isp_axi_wvalid(cpu_wvalid),
 .m_isp_axi_wready(cpu_wready),
 .m_isp_axi_bresp(cpu_bresp),
 .m_isp_axi_bvalid(cpu_bvalid),
 .m_isp_axi_bready(cpu_bready),
 .m_isp_axi_araddr(cpu_araddr),
 .m_isp_axi_arvalid(cpu_arvalid),
 .m_isp_axi_arready(cpu_arready),
 .m_isp_axi_rdata(cpu_rdata),
 .m_isp_axi_rresp(cpu_rresp),
 .m_isp_axi_rvalid(cpu_rvalid),
 .m_isp_axi_rready(cpu_rready));
ibex_isp_cfg_owner owner(.clk_i(vc),.rst_ni(rst),
 .ps_axi_awaddr(ps_awaddr),
 .ps_axi_awvalid(ps_awvalid),
 .ps_axi_awready(ps_awready),
 .ps_axi_wdata(ps_wdata),
 .ps_axi_wstrb(ps_wstrb),
 .ps_axi_wvalid(ps_wvalid),
 .ps_axi_wready(ps_wready),
 .ps_axi_bresp(ps_bresp),
 .ps_axi_bvalid(ps_bvalid),
 .ps_axi_bready(ps_bready),
 .ps_axi_araddr(ps_araddr),
 .ps_axi_arvalid(ps_arvalid),
 .ps_axi_arready(ps_arready),
 .ps_axi_rdata(ps_rdata),
 .ps_axi_rresp(ps_rresp),
 .ps_axi_rvalid(ps_rvalid),
 .ps_axi_rready(ps_rready),
 .cpu_axi_awaddr(cpu_awaddr),
 .cpu_axi_awvalid(cpu_awvalid),
 .cpu_axi_awready(cpu_awready),
 .cpu_axi_wdata(cpu_wdata),
 .cpu_axi_wstrb(cpu_wstrb),
 .cpu_axi_wvalid(cpu_wvalid),
 .cpu_axi_wready(cpu_wready),
 .cpu_axi_bresp(cpu_bresp),
 .cpu_axi_bvalid(cpu_bvalid),
 .cpu_axi_bready(cpu_bready),
 .cpu_axi_araddr(cpu_araddr),
 .cpu_axi_arvalid(cpu_arvalid),
 .cpu_axi_arready(cpu_arready),
 .cpu_axi_rdata(cpu_rdata),
 .cpu_axi_rresp(cpu_rresp),
 .cpu_axi_rvalid(cpu_rvalid),
 .cpu_axi_rready(cpu_rready),
 .m_axi_awaddr(m_awaddr),
 .m_axi_awvalid(m_awvalid),
 .m_axi_awready(m_awready),
 .m_axi_wdata(m_wdata),
 .m_axi_wstrb(m_wstrb),
 .m_axi_wvalid(m_wvalid),
 .m_axi_wready(m_wready),
 .m_axi_bresp(m_bresp),
 .m_axi_bvalid(m_bvalid),
 .m_axi_bready(m_bready),
 .m_axi_araddr(m_araddr),
 .m_axi_arvalid(m_arvalid),
 .m_axi_arready(m_arready),
 .m_axi_rdata(m_rdata),
 .m_axi_rresp(m_rresp),
 .m_axi_rvalid(m_rvalid),
 .m_axi_rready(m_rready));
isp_axi_regs #(.AE_STATS(1)) regs(.clk(vc),.resetn(rst),
 .s_axi_awaddr(m_awaddr),
 .s_axi_awvalid(m_awvalid && !hold_aw),
 .s_axi_awready(regs_awready),
 .s_axi_wdata(m_wdata),
 .s_axi_wstrb(m_wstrb),
 .s_axi_wvalid(m_wvalid),
 .s_axi_wready(m_wready),
 .s_axi_bresp(m_bresp),
 .s_axi_bvalid(m_bvalid),
 .s_axi_bready(m_bready),
 .s_axi_araddr(m_araddr),
 .s_axi_arvalid(m_arvalid),
 .s_axi_arready(m_arready),
 .s_axi_rdata(regs_rdata),
 .s_axi_rresp(m_rresp),
 .s_axi_rvalid(m_rvalid),
 .s_axi_rready(m_rready),
 .cfg_safe(1'b1),.frame_busy(1'b0),.frame_done(1'b0),.fault_count(32'b0),.fifo_level(13'b0),
 .cfg_pending(cfg_pending),.cfg_mode(cfg_mode),.ae_black(ae_black),.curve_rdata(10'b0),
 .ae_valid(1'b0),.ae_busy(1'b0),.ae_active(1'b0),.ae_seq(32'b0),.ae_frame(32'b0),.ae_mean(32'b0),.ae_count(32'b0),.ae_bad(32'b0),.ae_overrun(32'b0),.ae_sum(48'b0),.ae_result_region(2'b0),.ae_result_black(10'b0),.ae_x(32'b0),.ae_y(32'b0),.ae_width(32'b0),.ae_height(32'b0));
integer writes=0; reg [31:0] state=0, sig=0, errors=0, ack=0, dirty=0, before_val=0, restored=0; reg granted=0; reg [31:0] saved_before=0;
always @(posedge vc) if(m_wvalid && m_wready) begin
  writes<=writes+1;
  if (!granted) $fatal(1,"ISP write before grant");
end
always @(negedge clk) if(dut.data_gnt && dut.data_we) begin
 case(dut.data_addr)
  32'h23f00c: state=dut.data_wdata; 32'h23f014: errors=dut.data_wdata;
  32'h23f018: sig=dut.data_wdata; 32'h23f028: ack=dut.data_wdata;
  32'h23f040: before_val=dut.data_wdata; 32'h23f04c: restored=dut.data_wdata;
  32'h23f050: dirty=dut.data_wdata;
 endcase
end
task host_write(input [31:0] a,input [31:0] d); begin
 @(negedge clk);host_addr=a;host_data=d;host_aw=1;host_w=1;host_br=1;
 fork begin do @(posedge clk); while(!host_ar); @(negedge clk);host_aw=0; end
      begin do @(posedge clk); while(!host_wr); @(negedge clk);host_w=0; end join
 do @(posedge clk); while(!host_bv); if(host_resp!==0) $fatal(1,"host write failed"); @(negedge clk);host_br=0;
end endtask
initial begin
 repeat(4) @(negedge vc); rst=1; cr=1;
 wait(state==1);
 for(integer i=0;i<140;i=i+1) begin @(negedge vc); valid=1; sof=i==0; eol=i%10==9; end
 @(negedge vc); valid=0;sof=0;eol=0; repeat(60) @(negedge vc);fe=1; @(negedge vc);fe=0;
 host_write(32'h23f02c,32'h56494431);
 wait(state==2); repeat(200) @(posedge clk);
 if(writes!=0) $fatal(1,"unexpected writes");
 host_write(32'h23f020,32'h54455354);host_write(32'h23f024,32'h11111111);
 wait(ack==32'h11111111); if(state!==7 || (errors & 32'h20)==0 || writes!=0) $fatal(1,"ungranted command accepted");
 @(negedge clk); cpu_rst=0; repeat(10) @(negedge clk); cpu_rst=1;
 wait(state==1); host_write(32'h23f02c,32'h56494431); wait(state==2);
 @(negedge vc);ps_awaddr=16'hff00;ps_awvalid=1;ps_wdata=1;ps_wstrb=15;ps_wvalid=1;ps_bready=1;
 fork begin do @(posedge vc); while(!ps_awready); @(negedge vc);ps_awvalid=0; end
      begin do @(posedge vc); while(!ps_wready); @(negedge vc);ps_wvalid=0; end join
 do @(posedge vc); while(!ps_bvalid); if(ps_bresp!==0) $fatal(1,"grant failed");
 @(negedge vc);ps_bready=0;granted=1;
 wait(state==3);host_write(32'h23f020,32'h54455354);host_write(32'h23f024,32'h12345678);
 wait(ack==32'h12345678); repeat(5) @(posedge clk);
 if(state!==6 || sig!==32'h600dcf01 || errors!==0 || dirty!==0 || restored!==before_val || writes!==2)
  $fatal(1,"bad state=%h sig=%h errors=%h dirty=%h before=%h restored=%h writes=%d",state,sig,errors,dirty,before_val,restored,writes);
 $display("PASS unauthorized command and successful grant/restore");
 inject_fault=1; host_write(32'h23f024,32'h22222222); wait(ack==32'h22222222);
 if(state!==7 || dirty!==1 || (errors & 32'h10)==0 || writes!==4) $fatal(1,"restore fault not detected state=%h dirty=%h errors=%h writes=%d",state,dirty,errors,writes);
 $display("PASS corrupt restore readback detected");
 saved_before=before_val;
 @(negedge clk);cpu_rst=0;
 repeat(10) @(negedge clk); cpu_rst=1;
 wait(state==1); wait(state==7); repeat(5) @(posedge clk);
 if(dirty!==1 || (errors & 32'h10)==0 || before_val!==saved_before || writes!==4 || sig!==0) $fatal(1,"dirty reset failed closed state=%h dirty=%h errors=%h before=%h expected=%h writes=%d sig=%h",state,dirty,errors,before_val,saved_before,writes,sig);
 $display("PASS interrupted dirty reset fail closed"); $finish;
end
initial begin #5000000;$fatal(1,"timeout state=%h pc=%h",state,dut.instr_addr);end
endmodule
