`timescale 1ns/1ps

module isp_yuy2_nv12 #(
    parameter integer WIDTH  = 1280,
    parameter integer HEIGHT = 1024
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire [31:0] s_data,
    input  wire        s_valid,
    input  wire        s_sof,
    input  wire        s_eol,
    input  wire        s_fault,
    output reg  [15:0] y_data,
    output reg         y_valid,
    output reg         y_sof,
    output reg         y_eol,
    output reg         y_eof,
    input  wire        y_ready,
    output reg  [15:0] uv_data,
    output reg         uv_valid,
    output reg         uv_sof,
    output reg         uv_eol,
    output reg         uv_eof,
    input  wire        uv_ready,
    output reg         frame_abort,
    output reg         frame_done
);
    localparam integer CW = $clog2(WIDTH / 2 + 1);
    localparam integer RH = $clog2(HEIGHT + 1);

    reg [CW-1:0] col;
    reg [RH-1:0] row;
    reg active;
    reg finishing;
    reg [15:0] chroma [0:WIDTH/2-1];

    wire ys = !y_valid || y_ready;
    wire us = !uv_valid || uv_ready;
    wire start = s_valid && s_sof;
    wire [CW-1:0] x = start ? {CW{1'b0}} : col;
    wire [RH-1:0] r = start ? {RH{1'b0}} : row;
    wire last_col = (x == WIDTH / 2 - 1);
    wire bad = (s_eol != last_col);
    wire [8:0] u_sum = {1'b0, chroma[x][7:0]} +
                       {1'b0, s_data[15:8]} + 9'd1;
    wire [8:0] v_sum = {1'b0, chroma[x][15:8]} +
                       {1'b0, s_data[31:24]} + 9'd1;

    always @(posedge clk) begin
        if (!resetn) begin
            col         <= 0;
            row         <= 0;
            active      <= 0;
            finishing   <= 0;
            y_valid     <= 0;
            uv_valid    <= 0;
            y_data      <= 0;
            uv_data     <= 0;
            y_sof       <= 0;
            y_eol       <= 0;
            y_eof       <= 0;
            uv_sof      <= 0;
            uv_eol      <= 0;
            uv_eof      <= 0;
            frame_abort <= 0;
            frame_done  <= 0;
        end else begin
            frame_abort <= 0;
            frame_done  <= 0;

            if (y_valid && y_ready) begin
                y_valid <= 0;
            end
            if (uv_valid && uv_ready) begin
                uv_valid <= 0;
            end
            if (finishing && ys && us) begin
                finishing  <= 0;
                frame_done <= 1;
            end

            if (s_fault) begin
                if (active || finishing) begin
                    frame_abort <= 1;
                end
                active    <= 0;
                finishing <= 0;
            end else if (s_valid && (active || start)) begin
                if ((start && (active || (finishing && !(ys && us)))) ||
                    !ys || (r[0] && !us) || bad || r >= HEIGHT) begin
                    frame_abort <= 1;
                    active      <= 0;
                    finishing   <= 0;
                end else begin
                    y_data  <= {s_data[23:16], s_data[7:0]};
                    y_valid <= 1;
                    y_sof   <= start;
                    y_eol   <= last_col;
                    y_eof   <= last_col && (r == HEIGHT - 1);

                    if (!r[0]) begin
                        chroma[x] <= {s_data[31:24], s_data[15:8]};
                    end else begin
                        uv_data  <= {v_sum[8:1], u_sum[8:1]};
                        uv_valid <= 1;
                        uv_sof   <= (r == 1) && (x == 0);
                        uv_eol   <= last_col;
                        uv_eof   <= last_col && (r == HEIGHT - 1);
                    end

                    active <= 1;
                    if (last_col) begin
                        col <= 0;
                        row <= r + 1'b1;
                        if (r == HEIGHT - 1) begin
                            active    <= 0;
                            finishing <= 1;
                        end
                    end else begin
                        col <= x + 1'b1;
                        row <= r;
                    end
                end
            end
        end
    end
endmodule
