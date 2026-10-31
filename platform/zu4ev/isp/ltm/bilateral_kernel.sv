`timescale 1ns/1ps
// Two 5x5 windows, row-major, low bits first. Center is tap 12.
// 3 accumulation stages + 10 division stages, all with common stall enable.
module bilateral_kernel #(parameter integer RUNTIME_CONFIG=0) (
    input wire clk,resetn,ce,
    input wire [1:0] cfg_range,
    input wire [249:0] window0,window1,
    input wire s_valid,s_sof,s_eol,
    output wire [19:0] m_original,m_base,
    output wire [21:0] m_detail,
    output wire m_valid,m_sof,m_eol
);
    function automatic [7:0] range_weight(input [9:0] difference);
        begin
            if(RUNTIME_CONFIG && cfg_range==1) begin
                case(difference)
`include "range_lut32.svh"
                    default: range_weight=0;
                endcase
            end else if(RUNTIME_CONFIG && cfg_range==2) begin
                case(difference)
`include "range_lut128.svh"
                    default: range_weight=0;
                endcase
            end else begin
                case(difference)
`include "range_lut.svh"
                    default: range_weight=0;
                endcase
            end
        end
    endfunction
    function automatic integer spatial(input integer coordinate);
        begin
            case(coordinate)
                0,4: spatial=1;
                1,3: spatial=4;
                default: spatial=6;
            endcase
        end
    endfunction
    wire [249:0] windows[0:1];
    assign windows[0]=window0;
    assign windows[1]=window1;
    wire [9:0] bases[0:1];
    for(genvar lane=0;lane<2;lane=lane+1) begin: pixel_lane
        reg [13:0] weight[0:24];
        reg [23:0] product[0:24];
        reg [25:0] row_product[0:4];
        reg [15:0] row_weight[0:4];
        reg [25:0] total_product;
        reg [15:0] total_weight;
        for(genvar tap=0;tap<25;tap=tap+1) begin: weighted_tap
            wire [9:0] pixel=windows[lane][tap*10+:10];
            wire [9:0] center=windows[lane][120+:10];
            wire [9:0] difference=(pixel>center)?pixel-center:center-pixel;
            localparam integer SPACE=spatial(tap/5)*spatial(tap%5);
            wire [13:0] w=range_weight(difference)*SPACE;
            always @(posedge clk) begin
                if(!resetn) begin weight[tap]<=0; product[tap]<=0; end
                else if(ce) begin weight[tap]<=w; product[tap]<=w*pixel; end
            end
        end
        for(genvar row=0;row<5;row=row+1) begin: sum_row
            always @(posedge clk) begin
                if(!resetn) begin row_product[row]<=0; row_weight[row]<=0; end
                else if(ce) begin
                    row_product[row]<={2'b0,product[5*row]}+{2'b0,product[5*row+1]}
                        +{2'b0,product[5*row+2]}+{2'b0,product[5*row+3]}+{2'b0,product[5*row+4]};
                    row_weight[row]<={2'b0,weight[5*row]}+{2'b0,weight[5*row+1]}
                        +{2'b0,weight[5*row+2]}+{2'b0,weight[5*row+3]}+{2'b0,weight[5*row+4]};
                end
            end
        end
        always @(posedge clk) begin
            if(!resetn) begin total_product<=0; total_weight<=1; end
            else if(ce) begin
                total_product<=row_product[0]+row_product[1]+row_product[2]+row_product[3]+row_product[4];
                total_weight<=row_weight[0]+row_weight[1]+row_weight[2]+row_weight[3]+row_weight[4];
            end
        end
        wire [25:0] rounded=total_product+{11'b0,total_weight[15:1]};
        unsigned_divider divider(.clk(clk),.resetn(resetn),.ce(ce),
            .numerator(rounded),.denominator(total_weight),.quotient(bases[lane]));
    end
    reg [19:0] original[0:12];
    reg [12:0] valid_pipe,sof_pipe,eol_pipe;
    integer i;
    always @(posedge clk) begin
        if(!resetn) begin
            valid_pipe<=0; sof_pipe<=0; eol_pipe<=0;
            for(i=0;i<13;i=i+1) original[i]<=0;
        end else if(ce) begin
            original[0]<={window1[120+:10],window0[120+:10]};
            for(i=1;i<13;i=i+1) original[i]<=original[i-1];
            valid_pipe<={valid_pipe[11:0],s_valid};
            sof_pipe<={sof_pipe[11:0],s_valid && s_sof};
            eol_pipe<={eol_pipe[11:0],s_valid && s_eol};
        end
    end
    assign m_original=original[12];
    assign m_base={bases[1],bases[0]};
    assign m_detail[10:0]=$signed({1'b0,m_original[9:0]})-$signed({1'b0,bases[0]});
    assign m_detail[21:11]=$signed({1'b0,m_original[19:10]})-$signed({1'b0,bases[1]});
    assign m_valid=valid_pipe[12];
    assign m_sof=sof_pipe[12];
    assign m_eol=eol_pipe[12];
endmodule
