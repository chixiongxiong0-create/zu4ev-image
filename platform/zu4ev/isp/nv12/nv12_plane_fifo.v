`timescale 1ns/1ps
// Two pixels/clock packer and synchronous-read FIFO, one plane per instance.
module nv12_plane_fifo #(
    parameter integer WIDTH = 1280,
    parameter integer ROWS = 1024,
    parameter integer DEPTH = 256
) (
    input wire clk, resetn, clear, enable,
    input wire [15:0] s_data,
    input wire s_valid, s_eof,
    output wire s_ready,
    output reg done, error,
    output wire [127:0] m_data,
    output wire [15:0] m_strb,
    output wire m_valid,
    input wire m_ready,
    output wire [$clog2(DEPTH)+1:0] level
);
    localparam integer PW = $clog2(DEPTH);
    reg [143:0] memory [0:DEPTH-1];
    reg [PW-1:0] wr_ptr, rd_ptr;
    reg [PW:0] count;
    reg [143:0] head;
    reg head_valid;
    reg [127:0] partial;
    reg [2:0] lane;
    reg [31:0] column, row;
    wire input_fire = s_valid && s_ready;
    wire row_end = column == WIDTH-2;
    wire final_sample = row_end && row == ROWS-1;
    wire push = input_fire && (lane == 7 || row_end);
    wire prefetch = (!head_valid || m_ready) && count != 0;
    reg [127:0] packed_data;
    reg [15:0] packed_strb;

    assign s_ready = enable && !done && !error && count < DEPTH-1;
    assign m_data = head[127:0];
    assign m_strb = head[143:128];
    assign m_valid = head_valid;
    assign level = {1'b0, count} + head_valid;

    always @* begin
        packed_data = partial;
        packed_data[lane*16 +: 16] = s_data;
        packed_strb = 16'hffff >> (14 - {lane, 1'b0});
    end

    always @(posedge clk) begin
        if (!resetn || clear) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count <= 0;
            head <= 0;
            head_valid <= 0;
            partial <= 0;
            lane <= 0;
            column <= 0;
            row <= 0;
            done <= 0;
            error <= 0;
        end else begin
            if (head_valid && m_ready) begin
                head_valid <= 0;
            end
            if (prefetch) begin
                head <= memory[rd_ptr];
                head_valid <= 1;
                rd_ptr <= rd_ptr + 1'b1;
            end
            if (push) begin
                memory[wr_ptr] <= {packed_strb, packed_data};
                wr_ptr <= wr_ptr + 1'b1;
            end
            case ({push, prefetch})
                2'b10: begin count <= count + 1'b1; end
                2'b01: begin count <= count - 1'b1; end
                default: begin end
            endcase
            if (input_fire) begin
                if (s_eof != final_sample) begin
                    error <= 1;
                end
                if (push) begin
                    partial <= 0;
                    lane <= 0;
                end else begin
                    partial <= packed_data;
                    lane <= lane + 1'b1;
                end
                if (row_end) begin
                    column <= 0;
                    row <= row + 1'b1;
                end else begin
                    column <= column + 2;
                end
                if (final_sample) begin
                    done <= 1;
                end
            end
        end
    end
endmodule
