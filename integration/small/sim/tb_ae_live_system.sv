`timescale 1ns/1ps
module tb_ae_live_system;
wire [31:0] sensor_status;wire sensor_owner,sensor_run,sensor_stop,sensor_grant,scl_low,sda_low;
tri1 scl,sda;
assign scl=scl_low?1'b0:1'bz; assign sda=sda_low?1'b0:1'bz;
sc130_sensor_model sensor(.scl(scl),.sda(sda));
reg clk=0, vc=0, rst=0, cr=0, cpu_rst=1, hold_aw=0; wire regs_awready; always #5 clk=~clk; always #2.5 vc=~vc;
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
reg valid=0,sof=0,eol=0,fe=0; reg [9:0] raw_pixel=90;
 wire [31:0] seq,frame,mean,count,bad,over,x,y,w,h; wire [47:0] sum;
 wire v,busy,active; wire [1:0] region; wire [9:0] black;
 ae_stats_raw10 #(.WIDTH(20),.HEIGHT(14)) source(.clk(vc),.resetn(rst),.s_data({raw_pixel,raw_pixel}),.s_valid(valid),.s_sof(sof),.s_eol(eol),.s_packet_error(1'b0),.s_global_fault(1'b0),.cfg_enable(1'b1),.cfg_region(2'd3),.cfg_black(10'd52),.result_valid(v),.div_busy(busy),.active_enable(active),.result_seq(seq),.result_frame(frame),.result_mean(mean),.result_count(count),.bad_frames(bad),.overruns(over),.result_sum(sum),.result_region(region),.result_black(black),.roi_x(x),.roi_y(y),.roi_width(w),.roi_height(h));
 wire [15:0] fseq,fg;wire [13:0] sseq,sg;wire ri;wire [63:0] ft,st;
 ae_fe_event ev(.clk(vc),.resetn(rst),.fe_pulse(fe),.sof_pulse(sof),.ack_toggle(1'b0),.irq(ri),.frame_seq(fseq),.sof_seq(sseq),.frame_gray(fg),.sof_gray(sg),.fe_time(ft),.sof_time(st));
 wire [511:0] stats={h,w,y,x,over,bad,{20'b0,black,region},{29'b0,active,busy,v},16'b0,sum,count,mean,frame,seq,64'b0};

reg [31:0] host_addr=0,host_data=0; reg host_aw=0,host_w=0,host_br=0; wire host_ar,host_wr,host_bv; wire [1:0] host_resp;
ibex_small_system #(.RomFile("ae_live.mem"),.EnableSensorControl(1),.EnableIspAccess(1),.EnableIspConfig(1),.EnableCpuResetInput(1),.EnableInputMailbox(1)) dut(
 .sensor_owner_i(sensor_owner),.sensor_run_i(sensor_run),.sensor_stop_i(sensor_stop),
 .sensor_ps_scl_release_i(1'b1),.sensor_ps_sda_release_i(1'b1),.sensor_scl_i(scl),.sensor_sda_i(sda),
 .sensor_scl_low_o(scl_low),.sensor_sda_low_o(sda_low),.sensor_grant_o(sensor_grant),.sensor_status_o(sensor_status),
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
ibex_isp_cfg_owner #(.EnableSensorOwnership(1)) owner(.clk_i(vc),.rst_ni(rst),.sensor_status_async_i(sensor_status),.owner_o(sensor_owner),.run_o(sensor_run),.stop_o(sensor_stop),
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
 .ae_valid(v),.ae_busy(busy),.ae_active(active),.ae_seq(seq),.ae_frame(frame),.ae_mean(mean),.ae_count(count),.ae_bad(bad),.ae_overrun(over),.ae_sum(sum),.ae_result_region(region),.ae_result_black(black),.ae_x(x),.ae_y(y),.ae_width(w),.ae_height(h));
integer writes=0;reg [31:0] state=0, fault=0, signature=0, changes=0,mcause=0,mepc=0; integer i,j;
reg stopped=0,switched=0;integer dark_exposure=0;
reg [31:0] irq_count=0,fe_seen=0,stats_seen=0,mean_seen=0,records_seen=0;
reg [31:0] accepted_address=0; reg accepted_write=0;
always @(posedge clk) begin
 if(dut.data_gnt && dut.data_req) begin accepted_address<=dut.data_addr;accepted_write<=dut.data_we;end
 if(dut.data_gnt && dut.data_req && dut.data_addr==32'h23bfe4) $display("A1_STACK_REQUEST we=%b data=%h",dut.data_we,dut.data_wdata);
 if(dut.data_rvalid && accepted_address==32'h23bfe4) $display("A1_STACK_RESPONSE we=%b data=%h err=%b",accepted_write,dut.data_rdata,dut.data_err);
 if(dut.data_rvalid && dut.data_err) $display("DATA_ERROR addr=%h write=%b sel=%d",accepted_address,accepted_write,dut.gen_isp.selected_q);
end
always @(posedge vc) if(m_wvalid && m_wready) writes<=writes+1;
always @(negedge clk) if(dut.data_gnt && dut.data_we) begin
 case(dut.data_addr)
  32'h23e00c:state=dut.data_wdata;
  32'h23e014:fault=dut.data_wdata;
  32'h23e018:irq_count=dut.data_wdata;
  32'h23e01c:fe_seen=dut.data_wdata;
  32'h23e024:stats_seen=dut.data_wdata;
  32'h23e02c:mean_seen=dut.data_wdata;
  32'h23e038:changes=dut.data_wdata;
  32'h23e040:records_seen=dut.data_wdata;
  32'h23e044:mcause=dut.data_wdata;
  32'h23e048:mepc=dut.data_wdata;
  32'h23e050:signature=dut.data_wdata;
 endcase
end
task pswrite(input [15:0] a,input [31:0] value,input [1:0] expected);
 begin @(negedge vc);ps_awaddr=a;ps_awvalid=1;ps_wdata=value;ps_wstrb=15;ps_wvalid=1;ps_bready=1;
 fork begin do @(posedge vc); while(!ps_awready); @(negedge vc);ps_awvalid=0;end
 begin do @(posedge vc); while(!ps_wready); @(negedge vc);ps_wvalid=0;end join
 do @(posedge vc); while(!ps_bvalid);if(ps_bresp!==expected) $fatal(1,"PS %h response %h",a,ps_bresp);
 @(negedge vc);ps_bready=0; end
endtask
`ifndef AE_TEST_NACK
`ifndef AE_TEST_NO_FRAMES
initial begin
 wait(sensor.writes==1);
 pswrite('hff08,0,0);pswrite('hff00,0,2);
 if(!sensor_owner || !sensor_grant) $fatal(1,"early reclaim during exposure group");
 wait(state==4 && owner.sensor_status_sync_q[0] && owner.sensor_status_sync_q[9]==sensor_stop);
 if(sensor.writes<2 || sensor.reads<12 || changes<1) $fatal(1,"stop acknowledged before write group and readback");
 dark_exposure={sensor.registers['h3e01],sensor.registers['h3e02]};
 if(dark_exposure<=16'h1000) $fatal(1,"dark frame did not increase exposure");
 pswrite('hff00,0,0);wait(!sensor_grant);
 pswrite('hff00,1,0);wait(sensor_grant);pswrite('hff08,1,0);
 wait(state==3);stopped=1;
end
`endif
`endif
initial begin
`ifdef AE_TEST_NACK
 sensor.force_nack=1;
 repeat(5) @(negedge vc);rst=1;cr=1;
 wait(sensor_status[6]);pswrite('hff00,1,0);wait(sensor_grant);pswrite('hff08,1,0);
 wait(state==5);if(fault!==3 || signature!==0) $fatal(1,"NACK not fail-stop fault=%d signature=%h",fault,signature);
 $display("PASS real Ibex AE NACK fail-stop");$finish;
`elsif AE_TEST_NO_FRAMES
 repeat(5) @(negedge vc);rst=1;cr=1;
 wait(sensor_status[6]);pswrite('hff00,1,0);wait(sensor_grant);pswrite('hff08,1,0);
 wait(signature==32'h600dae01 || state==5);if(state==5) $fatal(1,"startup fault %d",fault);
 repeat(1000) @(negedge clk);
 // Inject a monotonic timer jump beyond one second; firmware is unmodified.
 force dut.gen_sensor.u_sensor.ticks_q=32'd110000000;
 wait(state==5);wait(signature==0);if(fault!==5) $fatal(1,"no-frame fail-stop fault=%d signature=%h",fault,signature);
 $display("PASS real Ibex AE no-frame timeout via timer jump");$finish;
`else
 repeat(5) @(negedge vc);rst=1;cr=1;
 wait(sensor_status[6]); pswrite('hff00,1,0);wait(sensor_grant);pswrite('hff08,1,0);
 wait(signature==32'h600dae01 || state==5);if(state==5) $fatal(1,"startup fault %d",fault);
 if(signature!==32'h600dae01 || sensor.reads<7) $fatal(1,"startup signature %h reads %d",signature,sensor.reads);
 for(j=0;j<24;j=j+1) begin
   for(i=0;i<140;i=i+1) begin @(negedge vc);valid=1;sof=(i==0);eol=(i%10==9);end
   @(negedge vc);valid=0;sof=0;eol=0;repeat(80000) @(negedge vc);fe=1;
   @(negedge vc);fe=0;
   // Hold the next FE/SOF long enough for bounded I2C writes and readback.
   repeat(60000) @(negedge vc);
   if(state==5) $fatal(1,"running fault %d mcause=%h mepc=%h",fault,mcause,mepc);
   if(stopped && !switched) begin raw_pixel=250;switched=1;end
   if(switched && changes>=2) begin
     if({sensor.registers['h3e01],sensor.registers['h3e02]}>=dark_exposure || sensor.writes<4 || sensor.reads<14)
       $fatal(1,"bright frame did not reduce exposure/readback");
     $display("PASS real Ibex AE sensor writes=%0d reads=%0d changes=%0d stop drain and dark/bright",sensor.writes,sensor.reads,changes);$finish;
   end
 end
 $fatal(1,"no AE change state=%d changes=%d irq=%d fe=%d stats=%d mean=%d records=%d sensor wr=%d rd=%d pc=%h",state,changes,irq_count,fe_seen,stats_seen,mean_seen,records_seen,sensor.writes,sensor.reads,dut.instr_addr);
`endif
end
initial begin #30000000;$fatal(1,"timeout state=%h fault=%h pc=%h",state,fault,dut.instr_addr);end
endmodule
