`timescale 1ns/1ps
module tb_ddr;
    parameter W=34, H=6;
    localparam STRIDE=((W+15)/16)*16+16;
    reg clk=0;
    always #2.5 clk=~clk;
    reg resetn=0, dv=0, abort_frame=0, rr=0;
    reg [31:0] base=4080, tag=0, stride=STRIDE;
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
    reg [15:0] yd=0, ud=0;
    reg yv=0, uv=0, ye=0, ue=0;
    reg [31:0] rng=32'hfedcba98;
    reg [7:0] mem [0:8000000];
    reg have_aw=0, pending=0, inject_error=0, hold_b=0;
    integer address, length, beat, delay_b=0, cycles=0, writes=0, responses=0;
    reg aw_stalled=0,w_stalled=0;
    reg [39:0] saved_aw;
    reg [144:0] saved_w;
    nv12_ddr_writer #(.WIDTH(W),.HEIGHT(H),.FIFO_DEPTH(64)) dut(
        .clk(clk),.resetn(resetn),.desc_valid(dv),.desc_ready(dr),
        .desc_base(base),.desc_stride(stride),.desc_tag(tag),
        .y_data(yd),.uv_data(ud),.y_valid(yv),.uv_valid(uv),.y_eof(ye),.uv_eof(ue),
        .y_ready(yr),.uv_ready(ur),.frame_abort(abort_frame),.quiescent(),
        .result_valid(rv),.result_error(re),.result_tag(rt),.result_ready(rr),
        .m_axi_awaddr(awaddr),.m_axi_awlen(awlen),.m_axi_awsize(awsize),.m_axi_awburst(awburst),
        .m_axi_awvalid(awvalid),.m_axi_awready(awready),
        .m_axi_wdata(wd),.m_axi_wstrb(ws),.m_axi_wlast(wlast),.m_axi_wvalid(wvalid),.m_axi_wready(wready),
        .m_axi_bresp(resp),.m_axi_bvalid(bv),.m_axi_bready(br));
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
    task descriptor(input integer t,input integer addr);
        begin
            @(negedge clk);base=addr;tag=t;dv=1;
            do @(posedge clk); while(!dr);
            @(negedge clk);dv=0;
        end
    endtask
    task feed_y(input integer t);
        integer n;
        begin
            for(n=0;n<W*H/2;n=n+1) begin
                @(negedge clk);yv=1;yd={pixel(n*2+1,0,t),pixel(n*2,0,t)};ye=(n==W*H/2-1);
                do @(posedge clk); while(!yr);
            end
            @(negedge clk);yv=0;ye=0;
        end
    endtask
    task feed_uv(input integer t);
        integer n;
        begin
            for(n=0;n<W*H/4;n=n+1) begin
                @(negedge clk);uv=1;ud={pixel(n*2+1,1,t),pixel(n*2,1,t)};ue=(n==W*H/4-1);
                do @(posedge clk); while(!ur);
            end
            @(negedge clk);uv=0;ue=0;
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
        integer row,col,offset,k;
        begin
            for(row=0;row<H+H/2;row=row+1) begin
                for(col=0;col<STRIDE;col=col+1) begin
                    offset=addr+row*STRIDE+col;
                    if(col>=W) begin if(mem[offset]!==8'ha5) $fatal(1,"padding overwritten");end
                    else if(mem[offset]!==pixel((row<H ? row : row-H)*W+col,row>=H,t))
                        $fatal(1,"byte mismatch row=%d col=%d actual=%h",row,col,mem[offset]);
                end
            end
        end
    endtask
    initial begin : run
        integer i;
        $display("DDR test W=%0d H=%0d seed=fedcba98",W,H);
        for(i=0;i<=8000000;i=i+1) mem[i]=8'ha5;
        repeat(4) @(negedge clk);resetn=1;
        descriptor(1,4080);
        fork feed_y(1);feed_uv(1); join
        result_check(0,1);compare_frame(1,4080);
        descriptor(2,4000000);
        fork feed_y(2);feed_uv(2); join
        result_check(0,2);compare_frame(2,4000000);
        $display("PASS two buffers, stride, byte compare, 4KiB, AXI stalls and delayed B, writes=%0d responses=%0d",writes,responses);
        // Abort while the B response is held; no release is permitted yet.
        hold_b=1;descriptor(3,4080);
        fork : abort_case
            feed_y(3);
            begin
                wait(have_aw);@(negedge clk);abort_frame=1;
                @(negedge clk);abort_frame=0;
                wait(pending);repeat(20) @(negedge clk);
                if(rv) $fatal(1,"abort returned before B");
                hold_b=0;
                result_check(1,3);
            end
        join_any
        disable abort_case;
        @(negedge clk);yv=0;uv=0;
        descriptor(4,4081);result_check(1,4);
        // DDR error ends a frame even when producers have not reached EOF.
        inject_error=1;descriptor(5,4080);
        fork : error_case
            feed_y(5);
            result_check(1,5);
        join_any
        disable error_case;
        @(negedge clk);yv=0;uv=0;inject_error=0;
        descriptor(6,4080);
        fork feed_y(6);feed_uv(6);join
        result_check(0,6);compare_frame(6,4080);
        $display("PASS abort drain, invalid descriptor, BRESP error and recovery");
        $finish;
    end
endmodule
