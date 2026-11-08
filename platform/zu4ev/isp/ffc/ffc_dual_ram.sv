`timescale 1ns/1ps
// Common-clock block RAM: read-first CPU/accumulator port and video/readback port.
// Storage and outputs have no reset; validity is owned by the caller.
module ffc_dual_ram #(
    parameter integer WIDTH=24, ADDR_BITS=12
)(
    input wire clk,
    input wire a_enable, a_write,
    input wire [ADDR_BITS-1:0] a_addr,
    input wire [WIDTH-1:0] a_data,
    output reg [WIDTH-1:0] a_q,
    input wire b_enable,
    input wire [ADDR_BITS-1:0] b_addr,
    output reg [WIDTH-1:0] b_q
);
    (* ram_style="block" *) reg [WIDTH-1:0] memory [0:(1<<ADDR_BITS)-1];
    always @(posedge clk) begin
        if(a_enable) begin
            if(a_write) memory[a_addr]<=a_data;
            a_q<=memory[a_addr];
        end
    end
    always @(posedge clk) begin
        if(b_enable) b_q<=memory[b_addr];
    end
endmodule
