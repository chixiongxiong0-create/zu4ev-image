`timescale 1ns/1ps
// Standalone RAW10 decomposition; dimensions/markers must match the frame.
// Replicated borders, two pixels/beat, explicit BMG IP line storage.
module bilateral_layers #(
    parameter integer RUNTIME_CONFIG=0,
    parameter integer WIDTH=1280,
    parameter integer HEIGHT=1024
) (
    input wire clk,resetn,
    input wire [1:0] cfg_range,
    input wire [19:0] s_data,
    input wire s_valid,s_sof,s_eol,
    output wire s_ready,
    output wire [19:0] m_original,m_base,
    output wire [21:0] m_detail,
    output wire m_valid,m_sof,m_eol,
    input wire m_ready
);
    localparam integer PAIRS=WIDTH/2;
    localparam integer YBITS=$clog2(HEIGHT+2);
    reg [9:0] x;
    reg [YBITS-1:0] y;
    reg [2:0] write_bank;
    reg right_flush;
    wire advance=!m_valid || m_ready;
    wire virtual_row=(y>=HEIGHT);
    assign s_ready=resetn && advance && !virtual_row && !right_flush;
    wire issue=resetn && advance && (right_flush || virtual_row || s_valid);
    wire read_issue=issue && !right_flush;
    wire write_issue=read_issue && !virtual_row;
    wire [19:0] bank_out[0:4];

    for(genvar bank=0;bank<5;bank=bank+1) begin: line_bank
        // A writes, B reads, both synchronous to clk. Never read the writing bank.
        ltm_line_bram memory (
            .clka(clk),.ena(write_issue && write_bank==bank),
            .wea(write_issue && write_bank==bank),.addra(x),.dina(s_data),
            .clkb(clk),.enb(read_issue && !(write_issue && write_bank==bank)),
            .addrb(x),.doutb(bank_out[bank])
        );
    end

    // One accepted transaction of metadata accompanies synchronous BRAM reads.
    reg pending,pending_right;
    reg [9:0] pending_x;
    reg [YBITS-1:0] pending_y;
    reg [2:0] pending_bank;
    reg [19:0] pending_data;
    wire [19:0] vertical[0:4];
    integer r;
    localparam [2:0] LAST_BANK=(HEIGHT-1)%5;
    for(genvar row=0;row<5;row=row+1)begin: vertical_select
        // (pending_y+row-4) mod5, using the existing three-bit rotating bank.
        // Avoid a signed 32-bit dynamic remainder on the 200MHz pixel path.
        wire [3:0] bank_sum={1'b0,pending_bank}+row+1;
        wire [2:0] bank_index=(bank_sum>=5)?bank_sum-5:bank_sum;
        assign vertical[row]=(pending_y<4-row)?
            ((pending_y==0)?pending_data:bank_out[0]):
            (pending_y>=HEIGHT+4-row)?bank_out[LAST_BANK]:
            ((row==4)&&(pending_y<HEIGHT))?pending_data:bank_out[bank_index];
    end

    reg [19:0] previous2[0:4],previous1[0:4];
    reg [249:0] window0,window1;
    reg window_valid,window_sof,window_eol;
    reg [59:0] horizontal;
    integer c;
    always @(posedge clk) begin
        if(!resetn) begin
            x<=0; y<=0; write_bank<=0; right_flush<=0;
            pending<=0; pending_right<=0; pending_x<=0; pending_y<=0; pending_bank<=0; pending_data<=0;
            window0<=0; window1<=0; window_valid<=0; window_sof<=0; window_eol<=0;
            horizontal=0;
            for(r=0;r<5;r=r+1) begin previous2[r]<=0; previous1[r]<=0; end
        end else if(advance) begin
            pending<=issue;
            if(issue) begin
                pending_right<=right_flush; pending_x<=x; pending_y<=y; pending_bank<=write_bank; pending_data<=s_data;
                if(right_flush) begin
                    right_flush<=0; x<=0;
                    if(y==HEIGHT+1) begin y<=0; write_bank<=0; end
                    else begin
                        y<=y+1'b1;
                        if(write_bank==4) write_bank<=0;
                        else write_bank<=write_bank+1'b1;
                    end
                end else if(x==PAIRS-1) right_flush<=1;
                else x<=x+1'b1;
            end
            window_valid<=pending && pending_y>=2 && (pending_right || pending_x!=0);
            window_sof<=pending && pending_y==2 && !pending_right && pending_x==1;
            window_eol<=pending && pending_y>=2 && pending_right;
            if(pending) begin
                for(r=0;r<5;r=r+1) begin
                    if(pending_right) begin
                        horizontal={{2{previous1[r][19:10]}},previous1[r],previous2[r]};
                    end else if(pending_x==0) begin
                        previous2[r]<={2{vertical[r][9:0]}};
                        previous1[r]<=vertical[r];
                        horizontal=0;
                    end else begin
                        horizontal={vertical[r],previous1[r],previous2[r]};
                        previous2[r]<=previous1[r]; previous1[r]<=vertical[r];
                    end
                    for(c=0;c<5;c=c+1) begin
                        window0[(r*5+c)*10+:10]<=horizontal[c*10+:10];
                        window1[(r*5+c)*10+:10]<=horizontal[(c+1)*10+:10];
                    end
                end
            end
        end
    end

    bilateral_kernel #(.RUNTIME_CONFIG(RUNTIME_CONFIG)) kernel (.cfg_range(cfg_range),.clk(clk),.resetn(resetn),.ce(advance),
        .window0(window0),.window1(window1),.s_valid(window_valid),
        .s_sof(window_sof),.s_eol(window_eol),.m_original(m_original),
        .m_base(m_base),.m_detail(m_detail),.m_valid(m_valid),.m_sof(m_sof),.m_eol(m_eol));

    // Source markers are a contract, not a resynchronization request.
    // synthesis translate_off
    initial begin
        if(WIDTH<4 || WIDTH>2048 || WIDTH%2 || HEIGHT<5)
            $fatal(1,"Unsupported WIDTH/HEIGHT");
    end
    always @(posedge clk) if(resetn && s_valid && s_ready) begin
        if(s_sof !== (x==0 && y==0) || s_eol !== (x==PAIRS-1))
            $fatal(1,"INPUT_MARKER_CONTRACT x=%0d y=%0d sof=%b eol=%b",x,y,s_sof,s_eol);
    end
    // synthesis translate_on
endmodule
