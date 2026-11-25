`timescale 1ns/1ps
module tb_capture;
    parameter W=1280, H=1024;
    localparam STRIDE=((W+15)/16)*16+16;
    reg clk=0;
    always #2.5 clk=~clk;
    reg resetn=0, dv=0, abort_frame=0, rr=0;
    reg [31:0] base=4080, tag=0, stride=STRIDE;
    reg [1:0] cfg_slot=0;
    reg rel=0; reg [31:0] reltag=0;
    wire cfgready, cfgerror, releaseerror, irq;
    wire [31:0] framebase, framestride, failed;
    wire dr, yr, ur, rv, re;
    wire [31:0] rt, awaddr;
    wire [7:0] awlen;
    wire [2:0] awsize;
    wire [1:0] awburst;
    wire awvalid, wvalid, wlast, br;
    wire [127:0] wd;
    wire [15:0] ws;
    reg awready=0, wready=0, bv=0;
    reg [1:0] resp=0;
    reg [31:0] sd=0; reg sv=0, ss=0, se=0; wire [31:0] dropped;
    reg [15:0] yd=0, ud=0;
    reg yv=0, uv=0, ye=0, ue=0;
    reg [31:0] rng=32'hfedcba98;
    reg [7:0] mem [0:8000000];
    reg have_aw=0, pending=0, inject_error=0, hold_b=0;
    integer address, length, beat, delay_b=0, cycles=0, writes=0, responses=0;
    reg aw_stalled=0,w_stalled=0;
    reg [39:0] saved_aw;
    reg [144:0] saved_w;
    nv12_capture_output #(.WIDTH(W),.HEIGHT(H),.FIFO_DEPTH(32)) dut(
        .enable(1'b1),.stop_request(1'b0),.idle(),
        .clk(clk),.resetn(resetn),.cfg_valid(dv),.cfg_ready(cfgready),
        .cfg_slot(cfg_slot),.cfg_base(base),.cfg_stride(stride),.cfg_error(cfgerror),
        .release_valid(rel),.release_tag(reltag),.release_error(releaseerror),
        .frame_base(framebase),.frame_stride(framestride),.failed_frames(failed),
        .irq_enable(1'b1),.irq(irq),
        .s_data(sd),.s_valid(sv),.s_sof(ss),.s_eol(se),.s_fault(abort_frame),.dropped_frames(dropped),
        .frame_valid(rv),.frame_tag(rt),.frame_ready(rr),
        .m_axi_awaddr(awaddr),.m_axi_awlen(awlen),.m_axi_awsize(awsize),.m_axi_awburst(awburst),
        .m_axi_awvalid(awvalid),.m_axi_awready(awready),
        .m_axi_wdata(wd),.m_axi_wstrb(ws),.m_axi_wlast(wlast),.m_axi_wvalid(wvalid),.m_axi_wready(wready),
        .m_axi_bresp(resp),.m_axi_bvalid(bv),.m_axi_bready(br));
    assign re=1'b0;
    assign dr=1'b0;
    function [7:0] pixel(input integer n,input integer plane,input integer t);
        pixel=(n*7+plane*101+t*31)&255;
    endfunction
    always @(negedge clk) begin
        rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
        awready=resetn && !have_aw && !pending && rng[0];
        wready=resetn && have_aw && rng[2];
    end
    always @(posedge clk) if(resetn) begin : memory_model
        integer k;
        cycles=cycles+1;
        if(cycles>15000000) $fatal(1,"timeout");
        if(aw_stalled && (!awvalid || {awaddr,awlen}!==saved_aw)) $fatal(1,"AW changed under stall");
        if(w_stalled && (!wvalid || {wd,ws,wlast}!==saved_w)) $fatal(1,"W changed under stall");
        aw_stalled=awvalid&&!awready;saved_aw={awaddr,awlen};
        w_stalled=wvalid&&!wready;saved_w={wd,ws,wlast};
        if(awvalid&&awready) begin
            if(have_aw||pending||awsize!=4||awburst!=1||awlen>15||awaddr[3:0]!=0 ||
               awaddr[11:0]+(awlen+1)*16>4096) $fatal(1,"bad AW");
            have_aw=1;address=awaddr;length=awlen+1;beat=0;
        end
        if(wvalid&&wready) begin
            if(!have_aw||wlast!==(beat==length-1)) $fatal(1,"bad WLAST");
            for(k=0;k<16;k=k+1) if(ws[k]) mem[address+beat*16+k]=wd[k*8+:8];
            beat=beat+1;writes=writes+1;
            if(wlast) begin have_aw=0;pending=1;delay_b=5+(rng[7:4]);end
        end
        if(pending&&!bv&&!hold_b) begin
            if(delay_b==0) begin bv<=1;resp<=inject_error ? 2'b10 : 2'b00;end
            else delay_b=delay_b-1;
        end
        if(bv&&br) begin bv<=0;pending=0;responses=responses+1;end
        if(rv&&(pending||have_aw||awvalid||wvalid)) $fatal(1,"early result");
    end
    task configure_slot(input integer slot,input integer addr);
        begin
            @(negedge clk);cfg_slot=slot;base=addr;dv=1;
            do @(posedge clk);while(!cfgready);
            @(negedge clk);dv=0;if(cfgerror) $fatal(1,"configuration error");
        end
    endtask
    task feed(input integer t);
        integer r,c;
        begin
            for(r=0;r<H;r=r+1) begin
                for(c=0;c<W;c=c+2) begin
                    @(negedge clk);sv=1;ss=(r==0&&c==0);se=(c==W-2);
                    sd={pixel(r*W+c,2,t),pixel(r*W+c+1,0,t),pixel(r*W+c,1,t),pixel(r*W+c,0,t)};
                end
            end
            @(negedge clk);sv=0;ss=0;se=0;dv=0;
        end
    endtask
    task result_check(input integer err,input integer t);
        begin
            wait(rv);@(negedge clk);
            if(re!==err[0]||rt!==t) $fatal(1,"result error/tag");
            repeat(5) begin @(negedge clk);if(!rv||re!==err[0]||rt!==t||dr) $fatal(1,"unstable result");end
            rr=1;@(negedge clk);rr=0;
        end
    endtask
    task compare_frame(input integer t,input integer addr);
        integer row,col,offset,k,expected,srcrow,component;
        begin
            for(row=0;row<H+H/2;row=row+1) begin
                for(col=0;col<STRIDE;col=col+1) begin
                    offset=addr+row*STRIDE+col;
                    if(col>=W) begin if(mem[offset]!==8'ha5) $fatal(1,"padding overwritten");end
                    else begin
                        if(row<H) expected=pixel(row*W+col,0,t);
                        else begin
                            srcrow=(row-H)*2;
                            component=(col%2==0)?1:2;
                            expected=(pixel(srcrow*W+(col/2)*2,component,t)+
                                      pixel((srcrow+1)*W+(col/2)*2,component,t)+1)/2;
                        end
                        if(mem[offset]!==expected[7:0]) $fatal(1,"sink byte mismatch row=%d col=%d",row,col);
                    end
                end
            end
        end
    endtask
    initial begin : run
        integer i;
        $display("DDR test W=%0d H=%0d seed=fedcba98",W,H);
        for(i=0;i<=8000000;i=i+1) mem[i]=8'ha5;
        repeat(4) @(negedge clk);resetn=1;
        configure_slot(0,4080);configure_slot(1,4000000);
        repeat(5) @(negedge clk);
        feed(1);result_check(0,0);compare_frame(1,4080);
        feed(2);result_check(0,1);compare_frame(2,4000000);
        feed(3);if(dropped!=1) $fatal(1,"held buffers overwritten");
        @(negedge clk);rel=1;reltag=0;
        @(negedge clk);rel=0;
        repeat(5) @(negedge clk);
        feed(4);wait(rv);if(!irq||framebase!=4080||framestride!=STRIDE) $fatal(1,"frame metadata or irq");
        result_check(0,0);compare_frame(4,4080);
        if(irq||failed!=0||releaseerror) $fatal(1,"completion state");
        $display("PASS combined output two-buffer rotation, held-buffer drop, explicit release, IRQ, DDR byte compare");
        $finish;
    end
endmodule
