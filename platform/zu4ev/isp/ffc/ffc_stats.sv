`timescale 1ns/1ps
// Frozen RAW cell acquisition. No partial batch is ever published as valid.
module ffc_stats #(
    parameter integer WIDTH=1280, HEIGHT=1024, SHIFT=5, FRAMES=32
)(
    input wire clk, resetn, start,
    input wire [19:0] s_data,
    input wire s_valid, s_sof, s_eol, s_fault,
    input wire read_enable,
    input wire [10:0] read_index,
    output wire [31:0] read_data,
    output wire busy,
    output reg done, failed,
    output reg [31:0] frames_done
);
    localparam integer COLS=WIDTH>>SHIFT, ROWS=HEIGHT>>SHIFT;
    localparam integer CELLS=COLS*ROWS, SPACING=1<<SHIFT;
    localparam [1:0] IDLE=0, CLEAR=1, WAIT_FRAME=2, CAPTURE=3;
    reg [1:0] state;
    reg [10:0] clear_index, x, y;
    reg in_frame;
    reg [15:0] segment_sum;
    wire [31:0] old_sum, cpu_sum;
    wire [10:0] pair_sum={1'b0,s_data[9:0]}+{1'b0,s_data[19:10]};
    wire [10:0] px=s_sof ? 11'd0 : x;
    wire [10:0] py=s_sof ? 11'd0 : y;
    wire [10:0] cell_index=(py>>SHIFT)*COLS+(px>>SHIFT);
    wire row_end=(px==WIDTH-2);
    wire frame_end=row_end && py==HEIGHT-1;
    wire capturing=(state==CAPTURE)||(state==WAIT_FRAME && s_valid && s_sof);
    wire bad=s_fault || (s_valid && capturing &&
        ((s_sof && in_frame) || (s_eol != row_end) || (!s_sof && !in_frame)));
    assign busy=(state!=IDLE);
    localparam integer RAM_AB=$clog2(CELLS);
    wire segment_first=(px & (SPACING-1))==0;
    wire segment_last=(px & (SPACING-1))==SPACING-2;
    wire accumulate=capturing && s_valid && !bad;
    wire ram_enable=(state==CLEAR) || (accumulate && (segment_first || segment_last));
    wire ram_write=(state==CLEAR) || (accumulate && segment_last);
    wire [RAM_AB-1:0] ram_addr=(state==CLEAR) ? clear_index : cell_index;
    wire [31:0] ram_data=(state==CLEAR) ? 32'd0 : old_sum+segment_sum+pair_sum;
    ffc_dual_ram #(.WIDTH(32),.ADDR_BITS(RAM_AB)) sums (
        .clk(clk),.a_enable(ram_enable),.a_write(ram_write),
        .a_addr(ram_addr),.a_data(ram_data),.a_q(old_sum),
        .b_enable(read_enable && done && read_index<CELLS),
        .b_addr(RAM_AB'(read_index)),.b_q(cpu_sum));
    assign read_data=done ? cpu_sum : 32'd0;
    always @(posedge clk) begin
        if(!resetn) begin
            state<=IDLE;done<=0;failed<=0;frames_done<=0;
            clear_index<=0;x<=0;y<=0;in_frame<=0;segment_sum<=0;
        end else if(start && !busy) begin
            state<=CLEAR;done<=0;failed<=0;frames_done<=0;
            clear_index<=0;x<=0;y<=0;in_frame<=0;segment_sum<=0;
        end else if(state==CLEAR) begin
            if(clear_index==CELLS-1) begin
                state<=WAIT_FRAME;
            end else begin
                clear_index<=clear_index+1'b1;
            end
        end else if((state==WAIT_FRAME || state==CAPTURE) && bad) begin
            state<=IDLE;failed<=1;done<=0;in_frame<=0;
        end else if(capturing && s_valid) begin
            state<=CAPTURE;
            if((px & (SPACING-1))==0) begin
                segment_sum<=pair_sum;
            end else begin
                segment_sum<=segment_sum+pair_sum;
            end
            in_frame<=1;
            if(row_end) begin
                x<=0;
                y<=py+1'b1;
                if(frame_end) begin
                    in_frame<=0;y<=0;frames_done<=frames_done+1'b1;
                    if(frames_done==FRAMES-1) begin
                        state<=IDLE;done<=1;
                    end
                end
            end else begin
                x<=px+11'd2;y<=py;
            end
        end
    end
endmodule
