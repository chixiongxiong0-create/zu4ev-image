`timescale 1ns/1ps
module isp_tnr_node #(parameter integer WIDTH=1280, HEIGHT=1024,
    parameter integer BIST_TEST_BYTES=1048576)(
    input wire clk, resetn, calib_done,
    input wire [31:0] s_data,
    input wire s_valid, s_sof, s_eol, s_fault,
    output wire [31:0] m_data,
    output wire m_valid, m_sof, m_eol, m_fault,
    input wire [15:0] s_axi_awaddr,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    input wire [31:0] s_axi_wdata,
    input wire [3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    output wire [1:0] s_axi_bresp,
    output wire s_axi_bvalid,
    input wire s_axi_bready,
    input wire [15:0] s_axi_araddr,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0] s_axi_rresp,
    output wire s_axi_rvalid,
    input wire s_axi_rready,
    output wire [31:0] m_axi_awaddr,
    output wire [7:0] m_axi_awlen,
    output wire m_axi_awvalid,
    input wire m_axi_awready,
    output wire [127:0] m_axi_wdata,
    output wire [15:0] m_axi_wstrb,
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input wire m_axi_wready,
    input wire [1:0] m_axi_bresp,
    input wire m_axi_bvalid,
    output wire m_axi_bready,
    output wire [31:0] m_axi_araddr,
    output wire [7:0] m_axi_arlen,
    output wire m_axi_arvalid,
    input wire m_axi_arready,
    input wire [127:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,
    input wire m_axi_rlast,
    input wire m_axi_rvalid,
    output wire m_axi_rready
);
    wire cfg_enable, cfg_pending, cfg_clear_history, cfg_safe, memtest_start;
    wire [8:0] cfg_alpha;
    wire [7:0] cfg_motion_lo, cfg_motion_hi;
    wire history_valid, core_busy, bist_busy, bist_done;
    wire [31:0] frame_count,motion_count,filtered_count,fault_count,ddr_error_count,bist_errors;
    wire [15:0] fifo_level;
    reg memtest_pending, bist_owned;
    // Request holds the next frame at its boundary until all core AXI retires.
    wire launch_bist=memtest_pending && cfg_safe && !cfg_enable &&
                     calib_done && !bist_owned;
    always @(posedge clk) begin
        if(!resetn) begin memtest_pending<=0; bist_owned<=0; end
        else begin
            if(memtest_start && calib_done && !cfg_enable && !bist_owned)
                memtest_pending<=1;
            if(memtest_pending && !calib_done) memtest_pending<=0;
            if(launch_bist) begin memtest_pending<=0; bist_owned<=1; end
            if(bist_owned && bist_done) bist_owned<=0;
        end
    end
    wire [31:0] core_awaddr;
    wire [7:0] core_awlen;
    wire core_awvalid;
    wire core_awready;
    wire [127:0] core_wdata;
    wire [15:0] core_wstrb;
    wire core_wlast;
    wire core_wvalid;
    wire core_wready;
    wire [1:0] core_bresp;
    wire core_bvalid;
    wire core_bready;
    wire [31:0] core_araddr;
    wire [7:0] core_arlen;
    wire core_arvalid;
    wire core_arready;
    wire [127:0] core_rdata;
    wire [1:0] core_rresp;
    wire core_rlast;
    wire core_rvalid;
    wire core_rready;
    wire [31:0] bist_awaddr;
    wire [7:0] bist_awlen;
    wire bist_awvalid;
    wire bist_awready;
    wire [127:0] bist_wdata;
    wire [15:0] bist_wstrb;
    wire bist_wlast;
    wire bist_wvalid;
    wire bist_wready;
    wire [1:0] bist_bresp;
    wire bist_bvalid;
    wire bist_bready;
    wire [31:0] bist_araddr;
    wire [7:0] bist_arlen;
    wire bist_arvalid;
    wire bist_arready;
    wire [127:0] bist_rdata;
    wire [1:0] bist_rresp;
    wire bist_rlast;
    wire bist_rvalid;
    wire bist_rready;
    tnr_axi_regs #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) regs (
        .clk(clk),.resetn(resetn),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .cfg_safe(cfg_safe && !bist_owned && !memtest_pending && !memtest_start),
        .history_valid(history_valid),.busy(core_busy),.calib_done(calib_done),
        .memtest_busy(bist_owned || memtest_pending),.memtest_done(bist_done),
        .memtest_errors(bist_errors),.frame_count(frame_count),.motion_count(motion_count),
        .filtered_count(filtered_count),.fault_count(fault_count),.ddr_error_count(ddr_error_count),
        .fifo_level(fifo_level),.cfg_enable(cfg_enable),.cfg_pending(cfg_pending),
        .cfg_clear_history(cfg_clear_history),.memtest_start(memtest_start),
        .cfg_alpha(cfg_alpha),.cfg_motion_lo(cfg_motion_lo),.cfg_motion_hi(cfg_motion_hi)
    );
    tnr_core #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) core (
        .clk(clk),.resetn(resetn),.cfg_enable(cfg_enable),
        .cfg_pending((cfg_pending && !bist_owned) || memtest_pending || memtest_start),
        .cfg_clear_history(cfg_clear_history || launch_bist),
        .cfg_alpha(cfg_alpha),.cfg_motion_lo(cfg_motion_lo),.cfg_motion_hi(cfg_motion_hi),
        .mem_ready(calib_done && !bist_owned),.cfg_safe(cfg_safe),
        .s_data(s_data),.s_valid(s_valid),.s_sof(s_sof),.s_eol(s_eol),.s_fault(s_fault),.s_ready(),
        .m_data(m_data),.m_valid(m_valid),.m_sof(m_sof),.m_eol(m_eol),.m_fault(m_fault),.m_ready(1'b1),
        .history_valid(history_valid),.busy(core_busy),.frame_done(),
        .frame_count(frame_count),.motion_count(motion_count),.filtered_count(filtered_count),
        .fault_count(fault_count),.ddr_error_count(ddr_error_count),.fifo_level(fifo_level),
        .m_axi_awaddr(core_awaddr),
        .m_axi_awlen(core_awlen),
        .m_axi_awvalid(core_awvalid),
        .m_axi_awready(core_awready),
        .m_axi_wdata(core_wdata),
        .m_axi_wstrb(core_wstrb),
        .m_axi_wlast(core_wlast),
        .m_axi_wvalid(core_wvalid),
        .m_axi_wready(core_wready),
        .m_axi_bresp(core_bresp),
        .m_axi_bvalid(core_bvalid),
        .m_axi_bready(core_bready),
        .m_axi_araddr(core_araddr),
        .m_axi_arlen(core_arlen),
        .m_axi_arvalid(core_arvalid),
        .m_axi_arready(core_arready),
        .m_axi_rdata(core_rdata),
        .m_axi_rresp(core_rresp),
        .m_axi_rlast(core_rlast),
        .m_axi_rvalid(core_rvalid),
        .m_axi_rready(core_rready)
    );
    tnr_ddr_bist #(.TEST_BYTES(BIST_TEST_BYTES)) bist (
        .clk(clk),.resetn(resetn),.start(launch_bist),.ready(calib_done),
        .busy(bist_busy),.done(bist_done),.error_count(bist_errors),
        .m_axi_awaddr(bist_awaddr),
        .m_axi_awlen(bist_awlen),
        .m_axi_awvalid(bist_awvalid),
        .m_axi_awready(bist_awready),
        .m_axi_wdata(bist_wdata),
        .m_axi_wstrb(bist_wstrb),
        .m_axi_wlast(bist_wlast),
        .m_axi_wvalid(bist_wvalid),
        .m_axi_wready(bist_wready),
        .m_axi_bresp(bist_bresp),
        .m_axi_bvalid(bist_bvalid),
        .m_axi_bready(bist_bready),
        .m_axi_araddr(bist_araddr),
        .m_axi_arlen(bist_arlen),
        .m_axi_arvalid(bist_arvalid),
        .m_axi_arready(bist_arready),
        .m_axi_rdata(bist_rdata),
        .m_axi_rresp(bist_rresp),
        .m_axi_rlast(bist_rlast),
        .m_axi_rvalid(bist_rvalid),
        .m_axi_rready(bist_rready)
    );
    assign m_axi_awaddr=bist_owned ? bist_awaddr:core_awaddr;
    assign m_axi_awlen=bist_owned ? bist_awlen:core_awlen;
    assign m_axi_awvalid=bist_owned ? bist_awvalid:core_awvalid;
    assign core_awready=m_axi_awready && !bist_owned;
    assign bist_awready=m_axi_awready && bist_owned;
    assign m_axi_wdata=bist_owned ? bist_wdata:core_wdata;
    assign m_axi_wstrb=bist_owned ? bist_wstrb:core_wstrb;
    assign m_axi_wlast=bist_owned ? bist_wlast:core_wlast;
    assign m_axi_wvalid=bist_owned ? bist_wvalid:core_wvalid;
    assign core_wready=m_axi_wready && !bist_owned;
    assign bist_wready=m_axi_wready && bist_owned;
    assign core_bresp=m_axi_bresp;
    assign bist_bresp=m_axi_bresp;
    assign core_bvalid=m_axi_bvalid && !bist_owned;
    assign bist_bvalid=m_axi_bvalid && bist_owned;
    assign m_axi_bready=bist_owned ? bist_bready:core_bready;
    assign m_axi_araddr=bist_owned ? bist_araddr:core_araddr;
    assign m_axi_arlen=bist_owned ? bist_arlen:core_arlen;
    assign m_axi_arvalid=bist_owned ? bist_arvalid:core_arvalid;
    assign core_arready=m_axi_arready && !bist_owned;
    assign bist_arready=m_axi_arready && bist_owned;
    assign core_rdata=m_axi_rdata;
    assign bist_rdata=m_axi_rdata;
    assign core_rresp=m_axi_rresp;
    assign bist_rresp=m_axi_rresp;
    assign core_rlast=m_axi_rlast;
    assign bist_rlast=m_axi_rlast;
    assign core_rvalid=m_axi_rvalid && !bist_owned;
    assign bist_rvalid=m_axi_rvalid && bist_owned;
    assign m_axi_rready=bist_owned ? bist_rready:core_rready;
endmodule

