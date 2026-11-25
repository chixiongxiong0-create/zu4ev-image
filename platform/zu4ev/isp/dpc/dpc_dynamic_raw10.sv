`timescale 1ns/1ps
// Online dual-pixel Mono RAW10 dynamic DPC. The window and kernel always run,
// so bypass, observe and repair share one latency and switching never tears a
// frame. Configuration commits atomically at the frame's first RAM read; data
// already in the pipeline keeps the settings latched at its own SOF.
module dpc_dynamic_raw10 #(
    parameter integer WIDTH = 1280,
    parameter integer HEIGHT = 1024
)(
    input  wire        clk,
    input  wire        resetn,
    input  wire [19:0] s_data,
    input  wire        s_valid,
    input  wire        s_sof,
    input  wire        s_eol,
    input  wire        s_packet_error,
    input  wire        s_global_fault,
    output wire [19:0] m_data,
    output wire        m_valid,
    output wire        m_sof,
    output wire        m_eol,
    output reg         m_packet_error,
    output reg         m_global_fault,
    input  wire        csr_write,
    input  wire        csr_read,
    input  wire [15:0] csr_waddr,
    input  wire [15:0] csr_raddr,
    input  wire [31:0] csr_wdata,
    output wire        csr_write_ok,
    output wire [31:0] csr_rdata
);
    wire [19:0]  win_center;
    wire [119:0] win_taps;
    wire         win_valid, win_sof, win_eol, win_eof;
    wire         win_row_int, win_rd_start, win_fault;
    wire [1:0]   win_lane_int;

    wire         stream_fault = s_packet_error || s_global_fault;
    wire         flush = stream_fault || win_fault;

    dpc_dynamic_window #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) window (
        .clk(clk),.resetn(resetn),
        .s_data(s_data),.s_valid(s_valid),.s_sof(s_sof),.s_eol(s_eol),
        .s_packet_error(s_packet_error),.s_global_fault(s_global_fault),
        .flush(flush),
        .m_center(win_center),.m_taps(win_taps),
        .m_valid(win_valid),.m_sof(win_sof),.m_eol(win_eol),.m_eof(win_eof),
        .m_row_interior(win_row_int),.m_lane_interior(win_lane_int),
        .rd_frame_start(win_rd_start),.fault(win_fault));

    // ------------------------------------------------------------------
    // Configuration. Shadow writes are accepted only with no commit pending;
    // the commit snapshot is the full shadow register file and applies at the
    // next frame start that is not squashed by a fault.
    // ------------------------------------------------------------------
    reg [1:0]  shadow_mode;
    reg        shadow_hot_en, shadow_cold_en;
    reg [9:0]  shadow_hot, shadow_cold, shadow_flat;
    reg [1:0]  active_mode;
    reg        active_hot_en, active_cold_en;
    reg [9:0]  active_hot, active_cold, active_flat;
    reg        pending;
    reg [31:0] apply_seq;
    reg [31:0] fault_events;
    reg        fault_seen;

    wire aligned = (csr_waddr[1:0] == 2'b00);
    wire mode_write = csr_write && aligned && (csr_waddr == 16'h3164) && !pending &&
                      (csr_wdata[31:4] == 0) && (csr_wdata[1:0] != 2'd3);
    wire thresh_write = csr_write && aligned && (csr_waddr == 16'h3168) && !pending &&
                        (csr_wdata[31:30] == 0);
    wire commit_write = csr_write && aligned && (csr_waddr == 16'h316c) && !pending &&
                        (csr_wdata == 32'd1);
    assign csr_write_ok = mode_write || thresh_write || commit_write;

    reg [31:0] k_frame_seq, k_frame_hot, k_frame_cold, k_frame_repair;

    dpc_dynamic_kernel #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) kernel (
        .clk(clk),.resetn(resetn),.flush(flush),
        .s_center(win_center),.s_taps(win_taps),
        .s_valid(win_valid),.s_sof(win_sof),.s_eol(win_eol),.s_eof(win_eof),
        .s_row_interior(win_row_int),.s_lane_interior(win_lane_int),
        .cfg_mode(active_mode),.cfg_hot_en(active_hot_en),.cfg_cold_en(active_cold_en),
        .cfg_hot_margin(active_hot),.cfg_cold_margin(active_cold),.cfg_flat_limit(active_flat),
        .m_data(m_data),.m_valid(m_valid),.m_sof(m_sof),.m_eol(m_eol),.m_eof(),
        .frame_seq(k_frame_seq),.frame_hot(k_frame_hot),
        .frame_cold(k_frame_cold),.frame_repair(k_frame_repair));

    always @(posedge clk) begin
        if (!resetn) begin
            shadow_mode <= 2'd0;
            shadow_hot_en <= 1'b1;
            shadow_cold_en <= 1'b1;
            shadow_hot <= 10'd32;
            shadow_cold <= 10'd32;
            shadow_flat <= 10'd24;
            active_mode <= 2'd0;
            active_hot_en <= 1'b1;
            active_cold_en <= 1'b1;
            active_hot <= 10'd32;
            active_cold <= 10'd32;
            active_flat <= 10'd24;
            pending <= 1'b0;
            apply_seq <= 32'd0;
            fault_events <= 32'd0;
            fault_seen <= 1'b0;
        end else begin
            if (mode_write) begin
                shadow_mode <= csr_wdata[1:0];
                shadow_hot_en <= csr_wdata[2];
                shadow_cold_en <= csr_wdata[3];
            end
            if (thresh_write) begin
                shadow_hot <= csr_wdata[9:0];
                shadow_cold <= csr_wdata[19:10];
                shadow_flat <= csr_wdata[29:20];
            end
            if (commit_write) begin
                pending <= 1'b1;
            end
            if (win_rd_start && pending && !flush) begin
                active_mode <= shadow_mode;
                active_hot_en <= shadow_hot_en;
                active_cold_en <= shadow_cold_en;
                active_hot <= shadow_hot;
                active_cold <= shadow_cold;
                active_flat <= shadow_flat;
                pending <= 1'b0;
                apply_seq <= apply_seq + 1'b1;
            end
            // One event per fault, not one per cycle of a held level.
            if (flush && !fault_seen) begin
                if (fault_events != 32'hffffffff) fault_events <= fault_events + 1'b1;
            end
            fault_seen <= flush;
        end
    end

    always @(posedge clk) begin
        if (!resetn) begin
            m_packet_error <= 1'b0;
            m_global_fault <= 1'b0;
        end else begin
            m_packet_error <= s_packet_error;
            m_global_fault <= s_global_fault || win_fault;
        end
    end

    // ------------------------------------------------------------------
    // Register file, 0x3160..0x318c. The read response is registered on
    // csr_read exactly like the existing static DPC bridge.
    // ------------------------------------------------------------------
    reg [31:0] rdata;
    always @(posedge clk) begin
        if (!resetn) begin
            rdata <= 32'd0;
        end else if (csr_read) begin
            case (csr_raddr)
                16'h3160: rdata <= 32'h44504344;
                16'h3164: rdata <= {28'd0, shadow_cold_en, shadow_hot_en, shadow_mode};
                16'h3168: rdata <= {2'd0, shadow_flat, shadow_cold, shadow_hot};
                16'h316c: rdata <= 32'd0;
                16'h3170: rdata <= {23'd0, pending, 4'd0,
                                    active_cold_en, active_hot_en, active_mode};
                16'h3174: rdata <= {2'd0, active_flat, active_cold, active_hot};
                16'h3178: rdata <= apply_seq;
                16'h317c: rdata <= k_frame_seq;
                16'h3180: rdata <= k_frame_hot;
                16'h3184: rdata <= k_frame_cold;
                16'h3188: rdata <= k_frame_repair;
                16'h318c: rdata <= fault_events;
                default:  rdata <= 32'd0;
            endcase
        end
    end
    assign csr_rdata = rdata;
endmodule
