`timescale 1ns/1ps
// Four exclusive buffer slots. Tags are slot indices, not physical addresses.
module nv12_buffer_pool #(parameter integer WIDTH=1280, HEIGHT=1024) (
    input wire clk, resetn,
    input wire cfg_valid,
    output wire cfg_ready,
    input wire [1:0] cfg_slot,
    input wire [31:0] cfg_base, cfg_stride,
    output reg cfg_error, release_error,
    output reg desc_valid,
    input wire desc_ready,
    output reg [31:0] desc_base, desc_stride, desc_tag,
    input wire result_valid, result_error,
    input wire [31:0] result_tag,
    output wire result_ready,
    output reg frame_valid,
    input wire frame_ready,
    output reg [31:0] frame_base, frame_stride, frame_tag,
    input wire release_valid,
    input wire [31:0] release_tag,
    output reg [31:0] failed_frames
);
    localparam [2:0] UNUSED=0, FREE=1, WRITING=2, READY=3, OFFERED=4, HELD=5, RESERVED=6;
    reg [2:0] status [0:3];
    reg [31:0] bases [0:3];
    reg [31:0] strides [0:3];
    reg [1:0] allocation_start;
    reg [1:0] choice, completed_choice;
    reg found, completed_found, overlap;
    reg [1:0] ready_fifo [0:3];
    reg [1:0] ready_rd, ready_wr;
    reg [2:0] ready_count;
    wire ready_push = result_valid && result_tag<4 &&
                      status[result_tag[1:0]]==WRITING && !result_error;
    wire ready_pop = !frame_valid && ready_count!=0;
    reg [63:0] other_end;
    wire [63:0] config_end = {32'b0,cfg_base} +
                             {32'b0,cfg_stride}*(HEIGHT+HEIGHT/2);
    wire config_bad = cfg_base[3:0]!=0 || cfg_stride[3:0]!=0 ||
                      cfg_stride<WIDTH || config_end>64'h100000000 || overlap;
    integer n, k;
    always @* begin
        found=0;
        choice=0;
        completed_found=ready_count!=0;
        completed_choice=ready_fifo[ready_rd];
        overlap=0;
        other_end=0;
        for (n=0; n<4; n=n+1) begin
            if (!found && status[(allocation_start+n)%4]==FREE) begin
                found=1;
                choice=(allocation_start+n)%4;
            end
            other_end={32'b0,bases[n]}+{32'b0,strides[n]}*(HEIGHT+HEIGHT/2);
            if (n!=cfg_slot && status[n]!=UNUSED &&
                {32'b0,cfg_base}<other_end && {32'b0,bases[n]}<config_end) begin
                overlap=1;
            end
        end
    end
    assign cfg_ready = (status[cfg_slot]==UNUSED || status[cfg_slot]==FREE) &&
                       !result_valid && !release_valid;
    assign result_ready = 1'b1;

    always @(posedge clk) begin
        if (!resetn) begin
            allocation_start<=0;
            ready_rd<=0;ready_wr<=0;ready_count<=0;
            desc_valid<=0;
            desc_base<=0;
            desc_stride<=0;
            desc_tag<=0;
            frame_valid<=0;
            frame_base<=0;
            frame_stride<=0;
            frame_tag<=0;
            cfg_error<=0;
            release_error<=0;
            failed_frames<=0;
            for (k=0;k<4;k=k+1) begin
                status[k]<=UNUSED;
                bases[k]<=0;
                strides[k]<=0;
            end
        end else begin
            cfg_error<=0;
            release_error<=0;
            if (ready_push) begin
                ready_fifo[ready_wr]<=result_tag[1:0];
                ready_wr<=ready_wr+1'b1;
            end
            if (ready_pop) begin ready_rd<=ready_rd+1'b1; end
            case ({ready_push,ready_pop})
                2'b10: begin ready_count<=ready_count+1'b1; end
                2'b01: begin ready_count<=ready_count-1'b1; end
                default: begin end
            endcase
            if (cfg_valid && cfg_ready) begin
                if (config_bad) begin cfg_error<=1; end
                else begin
                    bases[cfg_slot]<=cfg_base;
                    strides[cfg_slot]<=cfg_stride;
                    status[cfg_slot]<=FREE;
                end
            end
            if (!desc_valid && found && !cfg_valid) begin
                desc_valid<=1;
                desc_base<=bases[choice];
                desc_stride<=strides[choice];
                desc_tag<={30'b0,choice};
                status[choice]<=RESERVED;
            end
            if (desc_valid && desc_ready) begin
                desc_valid<=0;
                status[desc_tag[1:0]]<=WRITING;
                allocation_start<=desc_tag[1:0]+1'b1;
            end
            if (result_valid) begin
                if (result_tag<4 && status[result_tag[1:0]]==WRITING) begin
                    status[result_tag[1:0]]<=result_error ? FREE : READY;
                    if (result_error) begin failed_frames<=failed_frames+1'b1; end
                end else begin release_error<=1; end
            end
            if (!frame_valid && completed_found) begin
                frame_valid<=1;
                frame_base<=bases[completed_choice];
                frame_stride<=strides[completed_choice];
                frame_tag<={30'b0,completed_choice};
                status[completed_choice]<=OFFERED;
            end
            if (frame_valid && frame_ready) begin
                frame_valid<=0;
                status[frame_tag[1:0]]<=HELD;
            end
            if (release_valid) begin
                if (release_tag<4 && status[release_tag[1:0]]==HELD) begin
                    status[release_tag[1:0]]<=FREE;
                end else begin release_error<=1; end
            end
        end
    end
endmodule
