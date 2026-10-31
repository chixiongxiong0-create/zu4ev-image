`timescale 1ns/1ps
module tb_sensor_owner;
reg [31:0] sensor_status=0; wire sensor_owner,sensor_run;
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
wire [31:0] m_rdata;
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
reg req=0,we=0; reg [31:0] addr=0,wdata=0; reg [3:0] be=15; wire gnt,rvalid,err; wire [31:0] rdata;
wire dreq,dwe,dgnt,dvalid,derr; wire [31:0] daddr,ddata,drdata; wire [3:0] dbe;
ibex_isp_cfg_cdc cdc(.clk_i(clk),.rst_ni(rst),.cfg_clk_i(vc),.cfg_rst_ni(rst),.req_i(req),.we_i(we),.addr_i(addr),.wdata_i(wdata),.be_i(be),.gnt_o(gnt),.rvalid_o(rvalid),.err_o(err),.rdata_o(rdata),.req_o(dreq),.we_o(dwe),.addr_o(daddr),.wdata_o(ddata),.be_o(dbe),.gnt_i(dgnt),.rvalid_i(dvalid),.err_i(derr),.rdata_i(drdata));
ibex_native_to_axi_lite bridge(.clk_i(vc),.rst_ni(rst),.req_i(dreq),.we_i(dwe),.addr_i(daddr),.wdata_i(ddata),.be_i(dbe),.gnt_o(dgnt),.rvalid_o(dvalid),.err_o(derr),.rdata_o(drdata),
.m_axi_awaddr(cpu_awaddr),
.m_axi_awvalid(cpu_awvalid),
.m_axi_awready(cpu_awready),
.m_axi_wdata(cpu_wdata),
.m_axi_wstrb(cpu_wstrb),
.m_axi_wvalid(cpu_wvalid),
.m_axi_wready(cpu_wready),
.m_axi_bresp(cpu_bresp),
.m_axi_bvalid(cpu_bvalid),
.m_axi_bready(cpu_bready),
.m_axi_araddr(cpu_araddr),
.m_axi_arvalid(cpu_arvalid),
.m_axi_arready(cpu_arready),
.m_axi_rdata(cpu_rdata),
.m_axi_rresp(cpu_rresp),
.m_axi_rvalid(cpu_rvalid),
.m_axi_rready(cpu_rready));
ibex_isp_cfg_owner #(.EnableSensorOwnership(1)) owner(.clk_i(vc),.rst_ni(rst),.sensor_status_async_i(sensor_status),.owner_o(sensor_owner),.run_o(sensor_run),
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
 .s_axi_rdata(m_rdata),
 .s_axi_rresp(m_rresp),
 .s_axi_rvalid(m_rvalid),
 .s_axi_rready(m_rready),
 .cfg_safe(1'b1),.frame_busy(1'b0),.frame_done(1'b0),.fault_count(32'b0),.fifo_level(13'b0),
 .cfg_pending(cfg_pending),.cfg_mode(cfg_mode),.ae_black(ae_black),.curve_rdata(10'b0),
 .ae_valid(1'b0),.ae_busy(1'b0),.ae_active(1'b0),.ae_seq(32'b0),.ae_frame(32'b0),.ae_mean(32'b0),.ae_count(32'b0),.ae_bad(32'b0),.ae_overrun(32'b0),.ae_sum(48'b0),.ae_result_region(2'b0),.ae_result_black(10'b0),.ae_x(32'b0),.ae_y(32'b0),.ae_width(32'b0),.ae_height(32'b0));
integer writes=0; always @(posedge vc) if(m_wvalid && m_wready) writes<=writes+1;
task native(input bit wr,input [15:0] a,input [31:0] v,input [3:0] mask,input bit expected_err,input [31:0] expected);
 begin @(negedge clk); req=1;we=wr;addr=a;wdata=v;be=mask; do @(posedge clk); while(!gnt); @(negedge clk);req=0; do begin @(posedge clk); #1; end while(!rvalid); if(err!==expected_err || (!wr && !expected_err && rdata!==expected)) $fatal(1,"native %h err %b data %h",a,err,rdata); end
endtask
task pswrite(input [15:0] a,input [31:0] v,input [1:0] response);
 begin @(negedge vc);ps_awaddr=a;ps_awvalid=1;ps_wdata=v;ps_wstrb=15;ps_wvalid=1;ps_bready=1;
 fork begin do @(posedge vc); while(!ps_awready); @(negedge vc);ps_awvalid=0; end begin do @(posedge vc); while(!ps_wready); @(negedge vc);ps_wvalid=0; end join
 do @(posedge vc); while(!ps_bvalid); if(ps_bresp!==response) $fatal(1,"PS %h resp %b",a,ps_bresp); @(negedge vc);ps_bready=0; end
endtask
task psread(input [15:0] a,input [31:0] expected);
 begin @(negedge vc);ps_araddr=a;ps_arvalid=1;ps_rready=1;
 do @(posedge vc); while(!ps_arready); @(negedge vc);ps_arvalid=0;
 do @(posedge vc); while(!ps_rvalid); if(ps_rresp!==0 || ps_rdata!==expected) $fatal(1,"PS read %h got %h resp %h",a,ps_rdata,ps_rresp);
 @(negedge vc);ps_rready=0; end
endtask
initial begin
 repeat(4) @(negedge vc);rst=1;repeat(6) @(negedge vc);
 psread('hff00,0);psread('hff08,0);pswrite('hff08,1,2);
 pswrite('hff00,1,0);if(!sensor_owner) $fatal(1,"owner grant failed");
 psread('hff00,1);pswrite('hff08,1,0);if(!sensor_run) $fatal(1,"run grant failed");
 sensor_status=32'h4; repeat(5) @(negedge vc);psread('hff04,4);
 pswrite('hff00,0,2);if(!sensor_owner) $fatal(1,"reclaimed during run");
 pswrite('hff08,0,0);pswrite('hff00,0,2);
 if(!sensor_owner) $fatal(1,"reclaimed before quiesce");
 sensor_status=32'h1; repeat(5) @(negedge vc);psread('hff04,1);
 pswrite('hff00,0,2); // A stale quiescent bit is insufficient without stop acknowledgement.
 sensor_status=32'h201; repeat(5) @(negedge vc);psread('hff04,'h201);
 pswrite('hff00,0,0);if(sensor_owner) $fatal(1,"reclaim failed");
 native(1,'hff08,1,15,1,0);
 $display("PASS sensor owner ABI run quiesce readback");$finish;
end
initial begin #100000;$fatal(1,"timeout");end
endmodule
