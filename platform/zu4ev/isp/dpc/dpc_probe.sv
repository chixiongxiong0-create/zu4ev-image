`timescale 1ns/1ps
// Sparse candidate capture. The video path never waits for this block.
module dpc_probe #(
    parameter integer WIDTH=1280, HEIGHT=1024, CAPTURE_LIMIT=1024
)(
    input wire clk, resetn, start, low,
    input wire [9:0] threshold,
    input wire [19:0] data,
    input wire valid, sof, eol, fault,
    input wire read_enable, read_lane,
    input wire [9:0] read_index,
    output wire [31:0] read_data,
    output reg busy, done, overflow, failed,
    output reg [10:0] count0, count1,
    output reg [31:0] capture_seq
);
    reg receiving;
    reg [10:0] x;
    reg [9:0] y;
    wire [10:0] px = sof ? 11'd0 : x;
    wire [9:0] py = sof ? 10'd0 : y;
    wire line_end = px == WIDTH-2;
    wire frame_end = line_end && py == HEIGHT-1;
    wire take = busy && valid && (receiving || sof);
    wire malformed = fault || (take && ((receiving && sof) || eol != line_end));
    wire match0 = low ? data[9:0] <= threshold : data[9:0] >= threshold;
    wire match1 = low ? data[19:10] <= threshold : data[19:10] >= threshold;
    wire full = (match0 && count0 == CAPTURE_LIMIT) || (match1 && count1 == CAPTURE_LIMIT);
    wire write0 = take && !malformed && !full && match0;
    wire write1 = take && !malformed && !full && match1;
    wire [31:0] data0, data1;
    reg read_lane_d, read_valid_d;

    ffc_dual_ram #(.WIDTH(32),.ADDR_BITS(10)) lane0 (
        .clk(clk),.a_enable(write0),.a_write(1'b1),.a_addr(count0[9:0]),
        .a_data({11'd0,py,px}),.a_q(),
        .b_enable(read_enable && !read_lane && done),.b_addr(read_index),.b_q(data0));
    ffc_dual_ram #(.WIDTH(32),.ADDR_BITS(10)) lane1 (
        .clk(clk),.a_enable(write1),.a_write(1'b1),.a_addr(count1[9:0]),
        .a_data({11'd0,py,px[10:1],1'b1}),.a_q(),
        .b_enable(read_enable && read_lane && done),.b_addr(read_index),.b_q(data1));

    assign read_data = read_valid_d ? (read_lane_d ? data1 : data0) : 32'd0;
    always @(posedge clk) begin
        if (!resetn) begin
            read_valid_d <= 1'b0;
            read_lane_d <= 1'b0;
            busy <= 1'b0;
            done <= 1'b0;
            overflow <= 1'b0;
            failed <= 1'b0;
            receiving <= 1'b0;
            count0 <= 11'd0;
            count1 <= 11'd0;
            capture_seq <= 32'd0;
            x <= 11'd0;
            y <= 10'd0;
        end else begin
            read_lane_d <= read_lane;
            read_valid_d <= read_enable && done && {1'b0,read_index} < (read_lane ? count1 : count0);
            if (start && !busy) begin
                busy <= 1'b1;
                done <= 1'b0;
                overflow <= 1'b0;
                failed <= 1'b0;
                receiving <= 1'b0;
                count0 <= 11'd0;
                count1 <= 11'd0;
            end else if (busy && (malformed || (take && full))) begin
                busy <= 1'b0;
                receiving <= 1'b0;
                overflow <= take && full && !malformed;
                failed <= malformed;
            end else if (take) begin
                if (match0) begin count0 <= count0 + 1'b1; end
                if (match1) begin count1 <= count1 + 1'b1; end
                receiving <= !frame_end;
                x <= line_end ? 11'd0 : px + 11'd2;
                y <= line_end ? py + 1'b1 : py;
                if (frame_end) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    capture_seq <= capture_seq + 1'b1;
                end
            end
        end
    end
endmodule
