`timescale 1ns/1ps
// Ten fully pipelined restoring steps. The bilateral mean is in 0..1023.
// den != 0 and num/den <= 1023 are guaranteed by the kernel contract.
module unsigned_divider (
    input wire clk, resetn, ce,
    input wire [25:0] numerator,
    input wire [15:0] denominator,
    output wire [9:0] quotient
);
    wire [25:0] remainder_in [0:10];
    wire [15:0] divisor_in [0:10];
    wire [9:0] quotient_in [0:10];
    assign remainder_in[0]=numerator;
    assign divisor_in[0]=denominator;
    assign quotient_in[0]=0;
    for(genvar k=0;k<10;k=k+1) begin: divide_step
        reg [25:0] remainder_reg;
        reg [15:0] divisor_reg;
        reg [9:0] quotient_reg;
        wire [25:0] trial={10'b0,divisor_in[k]} << (9-k);
        always @(posedge clk) begin
            if(!resetn) begin
                remainder_reg<=0; divisor_reg<=1; quotient_reg<=0;
            end else if(ce) begin
                divisor_reg<=divisor_in[k];
                if(remainder_in[k]>=trial) begin
                    remainder_reg<=remainder_in[k]-trial;
                    quotient_reg<=quotient_in[k] | (10'b1 << (9-k));
                end else begin
                    remainder_reg<=remainder_in[k];
                    quotient_reg<=quotient_in[k];
                end
            end
        end
        assign remainder_in[k+1]=remainder_reg;
        assign divisor_in[k+1]=divisor_reg;
        assign quotient_in[k+1]=quotient_reg;
    end
    assign quotient=quotient_in[10];
endmodule
