`timescale 1ns/1ps
module nv12_axi_regs (
    input wire clk, resetn,
    input wire [7:0] s_axi_awaddr,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    input wire [31:0] s_axi_wdata,
    input wire [3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    output reg [1:0] s_axi_bresp,
    output reg s_axi_bvalid,
    input wire s_axi_bready,
    input wire [7:0] s_axi_araddr,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    output reg [31:0] s_axi_rdata,
    output reg [1:0] s_axi_rresp,
    output reg s_axi_rvalid,
    input wire s_axi_rready,
    output reg cfg_valid,
    input wire cfg_ready, cfg_error, release_error,
    output wire [1:0] cfg_slot,
    output reg [31:0] cfg_base, cfg_stride,
    input wire frame_valid,
    output reg frame_ready,
    input wire [31:0] frame_base, frame_stride, frame_tag,
    output reg release_valid,
    output reg [31:0] release_tag,
    output reg irq_enable,
    output reg capture_enable,
    output wire stop_request,
    input wire capture_idle,
    input wire [31:0] dropped_frames, failed_frames
);
    localparam [1:0] CAPTURE=0, COMMAND_WAIT=1, CHECK=2;
    reg [1:0] state;
    reg aw_pending, w_pending;
    reg [7:0] address;
    reg [31:0] data, slot;
    reg [3:0] strobes;
    reg [2:0] command;
    wire commit = state==CAPTURE && aw_pending && w_pending && !s_axi_bvalid;
    wire aw_fire = s_axi_awvalid && s_axi_awready;
    wire w_fire = s_axi_wvalid && s_axi_wready;
    wire ar_fire = s_axi_arvalid && s_axi_arready;
    assign s_axi_awready = resetn && state==CAPTURE && !aw_pending && !s_axi_bvalid;
    assign s_axi_wready = resetn && state==CAPTURE && !w_pending && !s_axi_bvalid;
    assign s_axi_arready = resetn && !s_axi_rvalid;
    assign cfg_slot = slot[1:0];
    assign stop_request = commit &&
        ((address==8'h20 && strobes==4'hf && data==8) ||
         (address==8'h08 && strobes[0] && !data[1]));

    function [31:0] merge_bytes;
        input [31:0] old_value, new_value;
        input [3:0] mask;
        integer n;
        begin
            for (n=0;n<4;n=n+1) begin
                merge_bytes[n*8 +: 8] = mask[n] ? new_value[n*8 +: 8] : old_value[n*8 +: 8];
            end
        end
    endfunction

    always @(posedge clk) begin
        if (!resetn) begin
            state<=CAPTURE;
            aw_pending<=0; w_pending<=0;
            address<=0; data<=0; strobes<=0; command<=0;
            slot<=0; cfg_base<=0; cfg_stride<=0; release_tag<=0;
            cfg_valid<=0; frame_ready<=0; release_valid<=0; irq_enable<=0; capture_enable<=0;
            s_axi_bvalid<=0; s_axi_bresp<=0;
            s_axi_rvalid<=0; s_axi_rresp<=0; s_axi_rdata<=0;
        end else begin
            if (aw_fire) begin aw_pending<=1; address<=s_axi_awaddr; end
            if (w_fire) begin w_pending<=1; data<=s_axi_wdata; strobes<=s_axi_wstrb; end
            if (s_axi_bvalid && s_axi_bready) begin s_axi_bvalid<=0; end
            if (s_axi_rvalid && s_axi_rready) begin s_axi_rvalid<=0; end
            if (ar_fire) begin
                s_axi_rvalid<=1; s_axi_rresp<=0; s_axi_rdata<=0;
                case (s_axi_araddr)
                    8'h00: begin s_axi_rdata<=32'h4e563132; end
                    8'h04: begin s_axi_rdata<=2; end
                    8'h08: begin s_axi_rdata<={30'b0,capture_enable,irq_enable}; end
                    8'h0c: begin s_axi_rdata<={29'b0,capture_idle,cfg_ready,frame_valid}; end
                    8'h10: begin s_axi_rdata<=slot; end
                    8'h14: begin s_axi_rdata<=cfg_base; end
                    8'h18: begin s_axi_rdata<=cfg_stride; end
                    8'h1c: begin s_axi_rdata<=release_tag; end
                    8'h24: begin s_axi_rdata<=frame_base; end
                    8'h28: begin s_axi_rdata<=frame_stride; end
                    8'h2c: begin s_axi_rdata<=frame_tag; end
                    8'h30: begin s_axi_rdata<=dropped_frames; end
                    8'h34: begin s_axi_rdata<=failed_frames; end
                    default: begin s_axi_rresp<=2'b10; end
                endcase
            end
            if (commit) begin
                aw_pending<=0; w_pending<=0;
                s_axi_bvalid<=1; s_axi_bresp<=0;
                case (address)
                    8'h08: begin
                        if (strobes[0]) begin
                            if (data[1] && !capture_enable && !capture_idle) begin
                                s_axi_bresp<=2'b10;
                            end else begin
                                irq_enable<=data[0];
                                capture_enable<=data[1];
                            end
                        end
                    end
                    8'h10: begin slot<=merge_bytes(slot,data,strobes); end
                    8'h14: begin cfg_base<=merge_bytes(cfg_base,data,strobes); end
                    8'h18: begin cfg_stride<=merge_bytes(cfg_stride,data,strobes); end
                    8'h1c: begin release_tag<=merge_bytes(release_tag,data,strobes); end
                    8'h20: begin
                        if (strobes!=4'hf || (data!=1 && data!=2 && data!=4 && data!=8)) begin
                            s_axi_bresp<=2'b10;
                        end else if (data==8) begin
                            capture_enable<=0;
                        end else if (data==1 && (!cfg_ready || slot>3)) begin
                            s_axi_bresp<=2'b10;
                        end else if (data==2 && !frame_valid) begin
                            s_axi_bresp<=2'b10;
                        end else begin
                            s_axi_bvalid<=0;
                            state<=COMMAND_WAIT;
                            command<=data[2:0];
                            cfg_valid<=data==1;
                            frame_ready<=data==2;
                            release_valid<=data==4;
                        end
                    end
                    default: begin s_axi_bresp<=2'b10; end
                endcase
            end
            if (state==COMMAND_WAIT) begin
                frame_ready<=0;
                release_valid<=0;
                if (command!=1 || cfg_ready) begin
                    cfg_valid<=0;
                    state<=CHECK;
                end
            end
            if (state==CHECK) begin
                s_axi_bvalid<=1;
                s_axi_bresp<=((command==1 && cfg_error) ||
                              (command==4 && release_error)) ? 2'b10 : 2'b00;
                state<=CAPTURE;
            end
        end
    end
endmodule
