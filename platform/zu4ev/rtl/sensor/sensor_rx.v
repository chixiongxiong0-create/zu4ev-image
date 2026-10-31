`timescale 1ns/1ps
module sensor_rx (
    input wire  mipi_clk_n,
    input wire [1:0] mipi_data_n,
    input wire  video_clk,
    input wire  lite_clk,
    input wire  rx_lite_resetn,
    input wire  rx_video_resetn,
    output wire  init_done,
    output wire  bus_error,
    output wire [31:0] config_reg,
    output wire [31:0] status_reg,
    output wire [31:0] interrupt_status,
    output wire [31:0] interrupt_enable,
    output wire [31:0] lane0_info,
    output wire [31:0] lane1_info,
    output wire [23:0] csi_data,
    output wire [95:0] csi_user,
    output wire  valid,
    output wire  eol,
    output wire  sof,
    output wire  phy_locked,
    output wire  frame_pulse,
    output wire  irq,
    output wire  phy_reset,
    output wire [1:0] phy_fault_sync,
    input wire  mipi_clk_p,
    input wire [1:0] mipi_data_p
);
    wire [11:0] awaddr,
        araddr;
    wire  awvalid,
        awready,
        wvalid,
        wready,
        bvalid,
        bready,
        arvalid,
        arready,
        rvalid,
        rready;
    wire [31:0] wdata,
        rdata;
    wire [3:0] wstrb;
    wire [1:0] bresp,
        rresp;
    wire fe_request;
    reg fe_ack;
    reg frame_pulse_reg;
    (* ASYNC_REG = "TRUE" *) reg [1:0] fe_request_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] fe_reset_release;
    wire fe_resetn = rx_lite_resetn & rx_video_resetn;
    assign frame_pulse = frame_pulse_reg;

    // Four-phase CDC: hold request until acknowledged, then wait for ack low
    // before clearing another FE. This also works when video_clk pauses.
    // Reset flushes pending notifications; release is local to video_clk.
    always @(posedge video_clk or negedge fe_resetn) begin
        if (!fe_resetn) begin
            fe_reset_release <= 0;
            fe_request_sync <= 0;
            fe_ack <= 0;
            frame_pulse_reg <= 0;
        end else begin
            fe_reset_release <= {fe_reset_release[0], 1'b1};
            fe_request_sync <= {fe_request_sync[0], fe_request};
            frame_pulse_reg <= 0;
            if (!fe_reset_release[1]) fe_ack <= 0;
            else if (fe_request_sync[1] && !fe_ack) begin
                frame_pulse_reg <= 1;
                fe_ack <= 1;
            end else if (!fe_request_sync[1]) fe_ack <= 0;
        end
    end
    
    csi_control control_i (
        .clk              (lite_clk),
        .resetn           (rx_lite_resetn),
        .m_axi_awaddr     (awaddr),
        .m_axi_awvalid    (awvalid),
        .m_axi_awready    (awready),
        .m_axi_wdata      (wdata),
        .m_axi_wstrb      (wstrb),
        .m_axi_wvalid     (wvalid),
        .m_axi_wready     (wready),
        .m_axi_bresp      (bresp),
        .m_axi_bvalid     (bvalid),
        .m_axi_bready     (bready),
        .m_axi_araddr     (araddr),
        .m_axi_arvalid    (arvalid),
        .m_axi_arready    (arready),
        .m_axi_rdata      (rdata),
        .m_axi_rresp      (rresp),
        .m_axi_rvalid     (rvalid),
        .m_axi_rready     (rready),
        .init_done        (init_done),
        .bus_error        (bus_error),
        .config_reg       (config_reg),
        .status_reg       (status_reg),
        .interrupt_status (interrupt_status),
        .interrupt_enable (interrupt_enable),
        .lane0_info       (lane0_info),
        .lane1_info       (lane1_info),
        .csi_irq          (irq),
        .fe_request       (fe_request),
        .fe_ack           (fe_ack),
        .event_resetn     (rx_video_resetn)
    );

    // -------------------------------------------------------------------------
    // 4. 双 lane MIPI CSI-2 接收器
    // -------------------------------------------------------------------------
    
`ifdef SC130_UVC
    
    assign sof=csi_user[0];
`endif
    wire  
        byteclk,
        phyclk;
`ifdef SC130_UVC
    csi2_rx_uvc receiver_i (
`else
    csi2_rx receiver_i (
`endif
        .lite_aclk             (lite_clk),
        .lite_aresetn          (rx_lite_resetn),
        .dphy_clk_200M         (video_clk),
        .video_aclk            (video_clk),
        .video_aresetn         (rx_video_resetn),
        .rxbyteclkhs           (byteclk),
        .clkoutphy_out         (phyclk),
        .pll_lock_out          (phy_locked),
        .system_rst_out        (phy_reset),
        .csirxss_csi_irq       (irq),
        // With the register interface enabled this IP output is tied low.
        // frame_pulse instead reports acknowledged ISR.FE service in video_clk;
        // its timestamp includes AXI and CDC latency, never a SOF substitute.
        .frame_rcvd_pulse_out  (),
        .csirxss_s_axi_awaddr  (awaddr[7:0]),
        .csirxss_s_axi_awvalid (awvalid),
        .csirxss_s_axi_awready (awready),
        .csirxss_s_axi_wdata   (wdata),
        .csirxss_s_axi_wstrb   (wstrb),
        .csirxss_s_axi_wvalid  (wvalid),
        .csirxss_s_axi_wready  (wready),
        .csirxss_s_axi_bresp   (bresp),
        .csirxss_s_axi_bvalid  (bvalid),
        .csirxss_s_axi_bready  (bready),
        .csirxss_s_axi_araddr  (araddr[7:0]),
        .csirxss_s_axi_arvalid (arvalid),
        .csirxss_s_axi_arready (arready),
        .csirxss_s_axi_rdata   (rdata),
        .csirxss_s_axi_rresp   (rresp),
        .csirxss_s_axi_rvalid  (rvalid),
        .csirxss_s_axi_rready  (rready),
        .video_out_tdata       (csi_data),
        .video_out_tvalid      (valid),
        .video_out_tready      (1'b1),
`ifdef SC130_UVC
        .video_out_tuser       (csi_user),
`else
        .video_out_tuser       (sof),
`endif
        .video_out_tlast       (eol),
        .video_out_tdest       (),
        .mipi_phy_if_clk_p     (mipi_clk_p),
        .mipi_phy_if_clk_n     (mipi_clk_n),
        .mipi_phy_if_data_p    (mipi_data_p),
        .mipi_phy_if_data_n    (mipi_data_n)
    );
`ifdef SC130_UVC
    (* ASYNC_REG="TRUE" *) reg [1:0] phy_fault_sync_reg=2'b11;
    always @(posedge video_clk) phy_fault_sync_reg<={phy_fault_sync_reg[0],phy_reset|~phy_locked};
`endif
`ifdef SC130_UVC
    assign phy_fault_sync = phy_fault_sync_reg;
`endif
endmodule
