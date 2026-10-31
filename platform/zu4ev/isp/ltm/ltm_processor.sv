`timescale 1ns/1ps
// Fixed-curve local tone processing: BLC -> bilateral -> T(B)+gain*D -> YUY2.
// Runtime configuration is held for each whole frame by the camera ingress.
module ltm_processor #(
    parameter integer RUNTIME_CONFIG=0,
    parameter integer WIDTH=1280, HEIGHT=1024,
    parameter integer DETAIL_GAIN_Q8=256,
    parameter integer BYPASS=0,
    parameter integer IDENTITY=0
) (
    input wire clk,resetn,
    input wire [1:0] cfg_mode,cfg_range,
    input wire [9:0] cfg_black,cfg_gain,
    input wire cfg_bank,curve_we,curve_re,cfg_tone_enable,
    input wire [9:0] curve_waddr,curve_wdata,curve_raddr,
    output wire [9:0] curve_rdata,
    input wire [19:0] s_data,
    input wire s_valid,s_sof,s_eol,
    output wire s_ready,
    output reg [31:0] m_data,
    output reg [19:0] m_original,m_base,m_reconstructed,
    output reg [21:0] m_detail,
    output reg m_valid,m_sof,m_eol,
    input wire m_ready
);
    // Debug original is black-corrected RAW in normal/identity mode and raw in
    // bypass mode. No normalization or 8-bit quantization before decomposition.
    wire bypass_mode=RUNTIME_CONFIG ? cfg_mode==2 : BYPASS;
    wire identity_mode=RUNTIME_CONFIG ? cfg_mode==3 : IDENTITY;
    wire global_mode=RUNTIME_CONFIG && cfg_mode==1;
    wire [9:0] black=RUNTIME_CONFIG ? cfg_black : 10'd52;
    wire [9:0] gain=RUNTIME_CONFIG ? cfg_gain : DETAIL_GAIN_Q8;
    reg [19:0] pre_data;
    reg pre_valid,pre_sof,pre_eol;
    wire layer_ready,layer_valid,layer_sof,layer_eol;
    wire [19:0] layer_original,layer_base;
    wire [21:0] layer_detail;
    wire pre_ready=!pre_valid || layer_ready;
    wire advance=!m_valid || m_ready;
    assign s_ready=resetn && pre_ready;
    function automatic [9:0] black_correct(input [9:0] raw);
        black_correct=(raw>black)?raw-black:10'd0;
    endfunction
    always @(posedge clk) begin
        if(!resetn) begin pre_data<=0; pre_valid<=0; pre_sof<=0; pre_eol<=0; end
        else if(pre_ready) begin
            pre_data<=bypass_mode?s_data:{black_correct(s_data[19:10]),black_correct(s_data[9:0])};
            pre_valid<=s_valid; pre_sof<=s_valid&&s_sof; pre_eol<=s_valid&&s_eol;
        end
    end
    bilateral_layers #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.RUNTIME_CONFIG(RUNTIME_CONFIG)) layers (
        .cfg_range(cfg_range),
        .clk(clk),.resetn(resetn),.s_data(pre_data),.s_valid(pre_valid),
        .s_sof(pre_sof),.s_eol(pre_eol),.s_ready(layer_ready),
        .m_original(layer_original),.m_base(layer_base),.m_detail(layer_detail),
        .m_valid(layer_valid),.m_sof(layer_sof),.m_eol(layer_eol),.m_ready(advance)
    );

    wire [9:0] tone0,tone1;
    wire [19:0] tone_address=global_mode ? layer_original : layer_base;
    generate if(RUNTIME_CONFIG) begin: programmable_curve
        wire [9:0] a[0:1],b[0:1];
        for(genvar bank=0;bank<2;bank=bank+1) begin: bank_memory
            wire active_bank=(cfg_bank==bank);
            ltm_tone_bank memory(
                .clka(clk),.ena(active_bank ? advance&&layer_valid : curve_we),
                .wea(!active_bank&&curve_we),
                .addra(active_bank ? tone_address[9:0] : curve_waddr),
                .dina(curve_wdata),.douta(a[bank]),
                .clkb(clk),.enb(active_bank ? advance&&layer_valid : curve_re),
                .web(1'b0),.addrb(active_bank ? tone_address[19:10] : curve_raddr),
                .dinb(10'd0),.doutb(b[bank]));
        end
        assign tone0=cfg_bank ? a[1] : a[0];
        assign tone1=cfg_bank ? b[1] : b[0];
        assign curve_rdata=cfg_bank ? b[0] : b[1];
    end else begin: fixed_curve
        ltm_tone_rom base_curve (
            .clka(clk),.ena(advance&&layer_valid),.addra(tone_address[9:0]),.douta(tone0),
            .clkb(clk),.enb(advance&&layer_valid),.addrb(tone_address[19:10]),.doutb(tone1));
        assign curve_rdata=0;
    end endgenerate
    reg rom_valid,rom_sof,rom_eol;
    reg [19:0] rom_original,rom_base;
    reg [21:0] rom_detail;
    reg recon_valid,recon_sof,recon_eol;
    reg [19:0] recon_original,recon_base,recon_value;
    reg [21:0] recon_detail;

    function automatic [9:0] compose(input [9:0] mapped,input signed [10:0] detail);
        integer scaled,total;
        begin
            scaled=detail*$signed({1'b0,gain});
            if(scaled<0) scaled=-((-scaled+128)/256);
            else scaled=(scaled+128)/256;
            total=$signed({1'b0,mapped})+scaled;
            if(total<0) compose=0;
            else if(total>1023) compose=1023;
            else compose=total[9:0];
        end
    endfunction
    function automatic [7:0] video_y(input [9:0] code);
        reg [18:0] scaled;
        begin scaled=code*19'd219+19'd511; video_y=8'd16+scaled/19'd1023; end
    endfunction
    always @(posedge clk) begin
        if(!resetn) begin
            rom_valid<=0; rom_sof<=0; rom_eol<=0; rom_original<=0; rom_base<=0; rom_detail<=0;
            recon_valid<=0; recon_sof<=0; recon_eol<=0; recon_original<=0; recon_base<=0;
            recon_detail<=0; recon_value<=0;
            m_valid<=0; m_sof<=0; m_eol<=0; m_original<=0; m_base<=0;
            m_detail<=0; m_reconstructed<=0; m_data<=32'h80108010;
        end else if(advance) begin
            rom_valid<=layer_valid; rom_sof<=layer_valid&&layer_sof; rom_eol<=layer_valid&&layer_eol;
            rom_original<=layer_original; rom_base<=layer_base; rom_detail<=layer_detail;
            recon_valid<=rom_valid; recon_sof<=rom_sof; recon_eol<=rom_eol;
            recon_original<=rom_original; recon_base<=rom_base; recon_detail<=rom_detail;
            if(bypass_mode || (RUNTIME_CONFIG && !cfg_tone_enable)) recon_value<=rom_original;
            else if(global_mode) recon_value<={tone1,tone0};
            else begin
                recon_value[9:0]<=compose(identity_mode?rom_base[9:0]:tone0,$signed(rom_detail[10:0]));
                recon_value[19:10]<=compose(identity_mode?rom_base[19:10]:tone1,$signed(rom_detail[21:11]));
            end
            m_valid<=recon_valid; m_sof<=recon_sof; m_eol<=recon_eol;
            m_original<=recon_original; m_base<=recon_base; m_detail<=recon_detail;
            m_reconstructed<=recon_value;
            m_data<={8'h80,video_y(recon_value[19:10]),8'h80,video_y(recon_value[9:0])};
        end
    end
    // synthesis translate_off
    initial if(DETAIL_GAIN_Q8<0 || DETAIL_GAIN_Q8>512)
        $fatal(1,"DETAIL_GAIN_Q8 must be 0..512");
    // synthesis translate_on
endmodule
