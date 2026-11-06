`timescale 1ns/1ps
module nv12_ddr_writer #(
    parameter integer WIDTH = 1280,
    parameter integer HEIGHT = 1024,
    parameter integer FIFO_DEPTH = 256
) (
    input wire clk, resetn,
    input wire desc_valid,
    output wire desc_ready,
    input wire [31:0] desc_base, desc_stride, desc_tag,
    input wire [15:0] y_data, uv_data,
    input wire y_valid, uv_valid, y_eof, uv_eof,
    output wire y_ready, uv_ready,
    input wire frame_abort,
    output wire quiescent,
    output reg result_valid, result_error,
    output reg [31:0] result_tag,
    input wire result_ready,
    output reg [31:0] m_axi_awaddr,
    output reg [7:0] m_axi_awlen,
    output wire [2:0] m_axi_awsize,
    output wire [1:0] m_axi_awburst,
    output reg m_axi_awvalid,
    input wire m_axi_awready,
    output wire [127:0] m_axi_wdata,
    output wire [15:0] m_axi_wstrb,
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input wire m_axi_wready,
    input wire [1:0] m_axi_bresp,
    input wire m_axi_bvalid,
    output wire m_axi_bready
);
    localparam [1:0] IDLE = 2'd0, WRITE = 2'd1, RESPONSE = 2'd2;
    localparam integer ROW_BEATS = (WIDTH+15)/16;
    localparam integer LW = $clog2(FIFO_DEPTH)+2;
    reg [1:0] state, next_state;
    reg owned, failed, turn, selected_uv;
    reg [31:0] stride, y_address, uv_address;
    localparam integer RCW = $clog2(ROW_BEATS+1);
    localparam integer YCW = $clog2(ROW_BEATS*HEIGHT+1);
    localparam integer UCW = $clog2(ROW_BEATS*(HEIGHT/2)+1);
    reg [YCW-1:0] y_left;
    reg [UCW-1:0] uv_left;
    reg [RCW-1:0] y_row_left, uv_row_left;
    reg [31:0] y_row_base, uv_row_base;
    reg [8:0] beats_left;
    wire [127:0] y_head, uv_head;
    wire [15:0] y_mask, uv_mask;
    wire y_head_valid, uv_head_valid, y_pop, uv_pop;
    wire y_input_ready, uv_input_ready, y_done, uv_done, y_error, uv_error;
    wire [LW-1:0] y_level, uv_level;
    wire desc_fire = desc_valid && desc_ready;
    wire enable = owned && !failed && !frame_abort;
    wire error_now = failed || frame_abort || y_error || uv_error;
    wire complete = y_left==0 && uv_left==0 && y_done && uv_done;
    wire aw_fire = m_axi_awvalid && m_axi_awready;
    wire w_fire = m_axi_wvalid && m_axi_wready;
    wire b_fire = m_axi_bvalid && m_axi_bready;
    reg [4:0] y_burst, uv_burst;
    wire y_eligible = y_left!=0 && y_level>=y_burst;
    wire uv_eligible = uv_left!=0 && uv_level>=uv_burst;
    wire choose_uv = uv_eligible && (!y_eligible || turn);
    wire launch = state==IDLE && owned && !error_now && !complete &&
                  (y_eligible || uv_eligible);
    wire [4:0] burst = choose_uv ? uv_burst : y_burst;
    wire [63:0] extent = {32'b0, desc_base} +
                          {32'b0, desc_stride} * (HEIGHT+HEIGHT/2);
    wire invalid_desc = desc_base[3:0]!=0 || desc_stride[3:0]!=0 ||
                        desc_stride<WIDTH || extent>64'h100000000;

    assign quiescent = !owned && !result_valid && state==IDLE &&
                       !m_axi_awvalid && beats_left==0;
    assign desc_ready = !owned && !result_valid;
    assign y_ready = owned ? y_input_ready : !result_valid;
    assign uv_ready = owned ? uv_input_ready : !result_valid;
    assign m_axi_awsize = 3'd4;
    assign m_axi_awburst = 2'b01;
    assign m_axi_wdata = selected_uv ? uv_head : y_head;
    assign m_axi_wstrb = selected_uv ? uv_mask : y_mask;
    assign m_axi_wvalid = state==WRITE && beats_left!=0 &&
                         (selected_uv ? uv_head_valid : y_head_valid);
    assign m_axi_wlast = beats_left==1;
    assign m_axi_bready = state==RESPONSE;
    assign y_pop = w_fire && !selected_uv;
    assign uv_pop = w_fire && selected_uv;

    nv12_plane_fifo #(.WIDTH(WIDTH), .ROWS(HEIGHT), .DEPTH(FIFO_DEPTH)) y_fifo (
        .clk(clk), .resetn(resetn), .clear(desc_fire), .enable(enable),
        .s_data(y_data), .s_valid(y_valid && owned), .s_eof(y_eof),
        .s_ready(y_input_ready), .done(y_done), .error(y_error),
        .m_data(y_head), .m_strb(y_mask), .m_valid(y_head_valid),
        .m_ready(y_pop), .level(y_level)
    );
    nv12_plane_fifo #(.WIDTH(WIDTH), .ROWS(HEIGHT/2), .DEPTH(FIFO_DEPTH)) uv_fifo (
        .clk(clk), .resetn(resetn), .clear(desc_fire), .enable(enable),
        .s_data(uv_data), .s_valid(uv_valid && owned), .s_eof(uv_eof),
        .s_ready(uv_input_ready), .done(uv_done), .error(uv_error),
        .m_data(uv_head), .m_strb(uv_mask), .m_valid(uv_head_valid),
        .m_ready(uv_pop), .level(uv_level)
    );

    always @* begin
        y_burst = y_row_left < 16 ? y_row_left : 32'd16;
        uv_burst = uv_row_left < 16 ? uv_row_left : 32'd16;
        if (y_burst > ((32'd4096-{20'b0,y_address[11:0]}) >> 4)) begin
            y_burst = (32'd4096-{20'b0,y_address[11:0]}) >> 4;
        end
        if (uv_burst > ((32'd4096-{20'b0,uv_address[11:0]}) >> 4)) begin
            uv_burst = (32'd4096-{20'b0,uv_address[11:0]}) >> 4;
        end
        next_state = state;
        case (state)
            IDLE: begin
                if (launch) begin next_state = WRITE; end
            end
            WRITE: begin
                if ((!m_axi_awvalid || aw_fire) &&
                    (beats_left==0 || (w_fire && beats_left==1))) begin
                    next_state = RESPONSE;
                end
            end
            RESPONSE: begin
                if (b_fire) begin next_state = IDLE; end
            end
            default: begin next_state = IDLE; end
        endcase
    end

    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE;
            owned <= 0;
            failed <= 0;
            turn <= 0;
            selected_uv <= 0;
            stride <= 0;
            y_address <= 0;
            y_row_base <= 0;
            uv_row_base <= 0;
            uv_address <= 0;
            y_left <= 0;
            uv_left <= 0;
            y_row_left <= 0;
            uv_row_left <= 0;
            beats_left <= 0;
            m_axi_awaddr <= 0;
            m_axi_awlen <= 0;
            m_axi_awvalid <= 0;
            result_valid <= 0;
            result_error <= 0;
            result_tag <= 0;
        end else begin
            state <= next_state;
            if (result_valid && result_ready) begin result_valid <= 0; end
            if (desc_fire) begin
                owned <= 1;
                failed <= invalid_desc;
                turn <= 0;
                stride <= desc_stride;
                y_address <= desc_base;
                y_row_base <= desc_base;
                uv_row_base <= desc_base + desc_stride*HEIGHT;
                uv_address <= desc_base + desc_stride*HEIGHT;
                y_left <= ROW_BEATS*HEIGHT;
                uv_left <= ROW_BEATS*(HEIGHT/2);
                y_row_left <= ROW_BEATS;
                uv_row_left <= ROW_BEATS;
                result_tag <= desc_tag;
            end
            if (owned && error_now) begin failed <= 1; end
            if (owned && state==IDLE && (error_now || complete)) begin
                owned <= 0;
                result_valid <= 1;
                result_error <= error_now;
            end
            if (aw_fire) begin m_axi_awvalid <= 0; end
            if (w_fire) begin beats_left <= beats_left - 1'b1; end
            if (b_fire && m_axi_bresp!=0) begin failed <= 1; end
            if (launch) begin
                selected_uv <= choose_uv;
                turn <= !choose_uv;
                beats_left <= {4'b0,burst};
                m_axi_awaddr <= choose_uv ? uv_address : y_address;
                m_axi_awlen <= {3'b0,burst} - 1'b1;
                m_axi_awvalid <= 1;
                if (choose_uv) begin
                    uv_left <= uv_left-uv_burst;
                    if (uv_row_left==uv_burst) begin
                        uv_row_left <= ROW_BEATS;
                        uv_address <= uv_row_base + stride;
                        uv_row_base <= uv_row_base + stride;
                    end else begin
                        uv_row_left <= uv_row_left-uv_burst;
                        uv_address <= uv_address + {23'b0,uv_burst,4'b0};
                    end
                end else begin
                    y_left <= y_left-y_burst;
                    if (y_row_left==y_burst) begin
                        y_row_left <= ROW_BEATS;
                        y_address <= y_row_base + stride;
                        y_row_base <= y_row_base + stride;
                    end else begin
                        y_row_left <= y_row_left-y_burst;
                        y_address <= y_address + {23'b0,y_burst,4'b0};
                    end
                end
            end
        end
    end
endmodule
