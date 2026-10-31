`timescale 1ns/1ps
module debug_monitor (
    input wire  camera_sda,
    output wire [94:0] gi,
    input wire [94:0] go,
    input wire [31:0] yuy2_data,
    input wire  yuy2_valid,
    input wire  yuy2_ready,
    input wire  yuy2_sof,
    input wire  yuy2_eol,
    input wire  cap_irq,
    input wire  yuy2_1_valid,
    input wire  cap1_irq,
    input wire  video_clk,
    input wire  locked,
    input wire  video_resetn,
    input wire  rx_lite_resetn,
    input wire  rx_video_resetn,
    input wire  capture_resetn,
    input wire  init_done,
    input wire  bus_error,
    input wire [31:0] config_reg,
    input wire [31:0] status_reg,
    input wire [31:0] interrupt_status,
    input wire [31:0] interrupt_enable,
    input wire [31:0] lane0_info,
    input wire [31:0] lane1_info,
    input wire [23:0] csi_data,
    input wire  valid,
    input wire  eol,
    input wire  sof,
    input wire  phy_locked,
    input wire  frame_pulse,
    input wire  ae_fe_irq,
    input wire [15:0] ae_fe_seq,
    input wire [13:0] ae_sof_seq,
    input wire [63:0] ae_fe_time,
    input wire [63:0] ae_sof_time,
    input wire  irq,
    input wire  phy_reset,
    input wire [1:0] phy_fault_sync,
    input wire  camera_scl
);
    wire [31:0] pixels = {6'b0, csi_data[19:10], 6'b0, csi_data[9:0]};
    // -------------------------------------------------------------------------
    // 6. EMIO 控制同步：bit2 请求快照，bit3 复位统计，bit12:8 选择快照字
    // -------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg [12:0] gc1 = 0, gc2 = 0;

    always @(posedge video_clk) begin
        gc1 <= go[12:0];
        gc2 <= gc1;
    end

    // -------------------------------------------------------------------------
    // 7. 图像统计与派生的行/帧事件脉冲
    // -------------------------------------------------------------------------
    wire [31:0] frame_count,
        line_count,
        total_word_count,
        last_frame_lines,
        last_line_pixels,
        frame_period_cycles,
        last_frame_words,
        data_xor,
        data_change_count;
    wire [9:0] data_min,
        data_max;
    wire  active_video,
        hs,
        vs;
    capture_monitor monitor_i (
        .clk                 (video_clk),
        .resetn              (video_resetn & ~gc2[3]),
        .axis_tvalid         (valid),
        .axis_tready         (1'b1),
        .axis_tuser          (sof),
        .axis_tlast          (eol),
        .axis_tdata          (pixels),
        .frame_count         (frame_count),
        .line_count          (line_count),
        .total_word_count    (total_word_count),
        .last_frame_lines    (last_frame_lines),
        .last_line_pixels    (last_line_pixels),
        .frame_period_cycles (frame_period_cycles),
        .last_frame_words    (last_frame_words),
        .data_min            (data_min),
        .data_max            (data_max),
        .data_xor            (data_xor),
        .data_change_count   (data_change_count),
        .active_video        (active_video),
        .hs                  (hs),
        .vs                  (vs)
    );
    // Snapshot counters at one video clock edge. Select an entry after the request settles.
    // Both clocks come from the same MMCM: retain normal timing analysis for this bus.

    // -------------------------------------------------------------------------
    // 8. 同源时钟下的诊断流水与原子计数快照
    // -------------------------------------------------------------------------
    reg [193:0] ds1 = 0,
        ds2 = 0;

    always @(posedge video_clk) begin
        ds1 <= {
            bus_error, init_done,
            config_reg, status_reg,
            interrupt_status, interrupt_enable,
            lane0_info, lane1_info
        };
        ds2 <= ds1;
    end
    // 快照索引：0 magic；1~3 累计帧/行/拍；4~7 上帧行数/行宽/周期/拍数；
    // 8~11 像素最小/最大/XOR/变化次数；12~16 CSI 配置/状态/ISR/lane0/lane1；
    // 17 标志位。索引与 tools/capture_status.c 保持一致。
    reg snap_seen = 0;
    reg [31:0] snapshot[0:21];
    integer i;

    always @(posedge video_clk) begin
        if (!video_resetn) begin
            snap_seen <= 0;
            for (i = 0; i < 22; i = i + 1)
                snapshot[i] <= 0;
        end else if (gc2[2] != snap_seen) begin
            snap_seen <= gc2[2];
            snapshot[0] <= 32'h53433130;
            snapshot[1] <= frame_count;
            snapshot[2] <= line_count;
            snapshot[3] <= total_word_count;
            snapshot[4] <= last_frame_lines;
            snapshot[5] <= last_line_pixels;
            snapshot[6] <= frame_period_cycles;
            snapshot[7] <= last_frame_words;
            snapshot[8] <= {22'b0, data_min};
            snapshot[9] <= {22'b0, data_max};
            snapshot[10] <= data_xor;
            snapshot[11] <= data_change_count;
            snapshot[12] <= ds2[191:160];
            snapshot[13] <= ds2[159:128];
            snapshot[14] <= ds2[127:96];
            snapshot[15] <= ds2[63:32];
            snapshot[16] <= ds2[31:0];
            // [7:0] = PHY reset, IRQ, frame pulse, PHY lock, bus error, init done, MMCM lock, video resetn.
            snapshot[17] <= {24'b0, phy_reset, irq, frame_pulse, phy_locked, ds2[193], ds2[192], locked, video_resetn};
            snapshot[18] <= ae_fe_time[31:0];
            snapshot[19] <= ae_fe_time[63:32];
            snapshot[20] <= ae_sof_time[31:0];
            snapshot[21] <= ae_sof_time[63:32];
        end
    end
    wire [31:0] selected = gc2[12:8] < 22 ? snapshot[gc2[12:8]] : 32'hdeadbeef;
    // GPIO input bits23:16: ABI marker, PHY reset/lock, bus fault, init,
    // capture/video/lite reset released. Direct status is polled until stable.
    wire [7:0] reset_status = {1'b1, phy_reset, phy_locked, bus_error,
        init_done, capture_resetn, rx_video_resetn, rx_lite_resetn};
    // GPIO bank 5: bit30 sticky FE IRQ, bits29:16 SOF Gray count, bits15:0 FE Gray count.
    assign gi = {ae_fe_irq, ae_sof_seq, ae_fe_seq,
                 selected, 8'b0, reset_status, 14'b0, camera_sda, camera_scl};

    // -------------------------------------------------------------------------
    // 9. ILA 探针：像素、事件、帧/行计数和帧周期
    // -------------------------------------------------------------------------
    camera_ila ila_i (
        .clk    (video_clk),
        .probe0 (pixels),
        // Probe1[9:8] sample the physical IIC bus with the same clock as FE/SOF.
        .probe1 ({22'b0, camera_scl, camera_sda,
                  phy_locked, locked, frame_pulse, vs, hs, active_video, eol, sof}),
        .probe2 (frame_count),
        .probe3 (line_count),
        .probe4 (last_frame_words),
        .probe5 (last_frame_lines),
        .probe6 (last_line_pixels),
        .probe7 (frame_period_cycles)
    );
`ifdef SC130_UVC
    uvc_ila uvc_ila_i(.clk(video_clk),.probe0(yuy2_data),
        .probe1({24'b0,cap1_irq,yuy2_1_valid,cap_irq,phy_fault_sync[1],yuy2_ready,yuy2_valid,yuy2_eol,yuy2_sof}));
`endif
endmodule
