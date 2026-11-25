`timescale 1ns/1ps
module tb_stop;
    parameter W=1280, H=64;
    localparam STRIDE=((W+15)/16)*16+16;
    reg clk=0;
    always #2.5 clk=~clk;
    reg resetn=0, dv=0, abort_frame=0, rr=0;
    reg [31:0] base=4080, tag=0, stride=STRIDE;
    reg [1:0] cfg_slot=0;
    reg rel=0; reg [31:0] reltag=0;
    wire cfgready, cfgerror, releaseerror, irq;
    reg [7:0] awaddr_ctrl=0,araddr=0;
    reg awvalid_ctrl=0,wvalid_ctrl=0,bready_ctrl=0,arvalid=0,rready=0;
    reg [31:0] wdata_ctrl=0;
    reg [3:0] wstrb_ctrl=0;
    wire awready_ctrl,wready_ctrl,bvalid_ctrl,arready,rvalid;
    wire [1:0] bresp_ctrl,rresp;
    wire [31:0] rdata;
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
    reg block_aw=0, block_w=0, watch_idle=0;
    reg have_aw=0, pending=0, inject_error=0, hold_b=0;
    integer address, length, beat, delay_b=0, cycles=0, writes=0, responses=0;
    reg aw_stalled=0,w_stalled=0;
    reg [39:0] saved_aw;
    reg [144:0] saved_w;
    nv12_capture_peripheral #(.WIDTH(W),.HEIGHT(H),.FIFO_DEPTH(32)) dut(
        .clk(clk),.resetn(resetn),.s_data(sd),.s_valid(sv),.s_sof(ss),.s_eol(se),.s_fault(abort_frame),.irq(irq),
        .s_axi_awaddr(awaddr_ctrl),.s_axi_awvalid(awvalid_ctrl),.s_axi_awready(awready_ctrl),
        .s_axi_wdata(wdata_ctrl),.s_axi_wstrb(wstrb_ctrl),.s_axi_wvalid(wvalid_ctrl),.s_axi_wready(wready_ctrl),
        .s_axi_bresp(bresp_ctrl),.s_axi_bvalid(bvalid_ctrl),.s_axi_bready(bready_ctrl),
        .s_axi_araddr(araddr),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
        .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
        .m_axi_awaddr(awaddr),.m_axi_awlen(awlen),.m_axi_awsize(awsize),.m_axi_awburst(awburst),
        .m_axi_awvalid(awvalid),.m_axi_awready(awready),
        .m_axi_wdata(wd),.m_axi_wstrb(ws),.m_axi_wlast(wlast),.m_axi_wvalid(wvalid),.m_axi_wready(wready),
        .m_axi_bresp(resp),.m_axi_bvalid(bv),.m_axi_bready(br));
    assign re=1'b0;
    assign rv=irq;
    assign dr=1'b0;
    function [7:0] pixel(input integer n,input integer plane,input integer t);
        pixel=(n*7+plane*101+t*31)&255;
    endfunction
    always @(negedge clk) begin
        rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
        awready=resetn && !have_aw && !pending && !block_aw && rng[0];
        wready=resetn && have_aw && !block_w && rng[2];
    end
    always @(posedge clk) if(resetn) begin : memory_model
        integer k;
        cycles=cycles+1;
        if(watch_idle && (awvalid||wvalid||br||have_aw||pending)) $fatal(1,"DDR activity after IDLE");
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
            write_reg('h10,slot,15,0,0);
            write_reg('h14,addr,15,1,0);
            write_reg('h18,STRIDE,15,0,0);
            write_reg('h20,1,15,1,0);
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
            wait(irq);
            read_reg('h2c,t,0);
            read_reg('h28,STRIDE,0);
            read_reg('h24,t==0?4080:4000000,0);
            write_reg('h20,2,15,0,0);
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
    task write_reg(input [7:0] addr,input [31:0] value,input [3:0] mask,input integer order,input [1:0] expected);
        begin
            fork
                begin
                    repeat(order==0?1:4) @(negedge clk);
                    awaddr_ctrl=addr;awvalid_ctrl=1;
                    do @(posedge clk);while(!awready_ctrl);
                    @(negedge clk);awvalid_ctrl=0;
                end
                begin
                    repeat(order==0?4:1) @(negedge clk);
                    wdata_ctrl=value;wstrb_ctrl=mask;wvalid_ctrl=1;
                    do @(posedge clk);while(!wready_ctrl);
                    @(negedge clk);wvalid_ctrl=0;
                end
            join
            wait(bvalid_ctrl);@(negedge clk);
            repeat(3) begin
                if(!bvalid_ctrl||bresp_ctrl!==expected||awready_ctrl||wready_ctrl) $fatal(1,"bad B response %h = %h",addr,bresp_ctrl);
                @(negedge clk);
            end
            bready_ctrl=1;@(negedge clk);bready_ctrl=0;
        end
    endtask
    task read_reg(input [7:0] addr,input [31:0] expected,input [1:0] response);
        begin
            @(negedge clk);araddr=addr;arvalid=1;
            do @(posedge clk);while(!arready);
            @(negedge clk);arvalid=0;
            wait(rvalid);
            repeat(3) begin
                @(negedge clk);
                if(!rvalid||rdata!==expected||rresp!==response) $fatal(1,"bad read %h data=%h resp=%h",addr,rdata,rresp);
            end
            rready=1;@(negedge clk);rready=0;
        end
    endtask

    task status_read(output reg [31:0] value);
        begin
            @(negedge clk);araddr='h0c;arvalid=1;
            do @(posedge clk);while(!arready);
            @(negedge clk);arvalid=0;
            wait(rvalid);value=rdata;
            if(rresp!=0) $fatal(1,"status read error");
            rready=1;@(negedge clk);rready=0;
        end
    endtask
    task wait_idle;
        reg [31:0] status;
        integer polls;
        begin
            status=0;polls=0;
            while(!status[2]) begin
                status_read(status);polls=polls+1;
                if(polls>500) $fatal(1,"IDLE timeout");
            end
            watch_idle=1;
            read_reg(8,1,0);
        end
    endtask
    task setup;
        begin
            @(negedge clk);resetn=0;sv=0;ss=0;se=0;watch_idle=0;
            block_aw=0;block_w=0;hold_b=0;
            repeat(4) @(negedge clk);resetn=1;
            configure_slot(0,4080);
            repeat(5) @(negedge clk);
            // Reset is disabled; software explicitly enables capture.
            write_reg(8,3,15,0,0);
        end
    endtask
    task blocked_stop(input integer mode);
        reg [31:0] status;
        integer saved_writes;
        begin
            setup();
            block_aw=(mode==0);block_w=(mode==1);hold_b=(mode>=2);
            fork
                feed(10+mode);
                begin
                    case(mode)
                        0: wait(awvalid);
                        1: wait(have_aw && wvalid);
                        2: wait(pending);
                        3: wait(dut.capture.sink.writer.y_fifo.count==31);
                    endcase
                    write_reg('h20,8,15,0,0);
                    status_read(status);
                    if(status[2]) $fatal(1,"early IDLE with outstanding AXI mode=%0d",mode);
                    // Re-enable during drain must fail and leave ENABLE low.
                    write_reg(8,3,15,1,2);
                    repeat(12) @(negedge clk);
                    status_read(status);if(status[2]) $fatal(1,"unsafe timeout fabricated IDLE");
                    block_aw=0;block_w=0;hold_b=0;
                    wait_idle();saved_writes=writes;
                    // STOP is idempotent; continued source traffic must be ignored.
                    write_reg('h20,8,15,1,0);
                    repeat(50) @(negedge clk);
                    if(writes!=saved_writes) $fatal(1,"write after stop");
                end
            join
            if(irq) $fatal(1,"aborted frame exposed");
            read_reg('h34,1,0);
            // Resume only on a fresh SOF, without resetting the pool.
            watch_idle=0;write_reg(8,3,15,0,0);
            saved_writes=writes;
            @(negedge clk);sv=1;ss=0;se=0;
            repeat(100) @(negedge clk);
            sv=0;
            if(writes!=saved_writes) $fatal(1,"restart accepted middle of frame");
            feed(20+mode);result_check(0,0);compare_frame(20+mode,4080);
            write_reg('h1c,0,15,0,0);write_reg('h20,4,15,1,0);
            write_reg('h20,8,15,0,0);wait_idle();
            $display("PASS STOP mode=%0d, no early IDLE, drain/reject-enable/no writes, restart byte comparison",mode);
        end
    endtask
    initial begin : run_stop
        integer i, saved_writes;
        reg [31:0] status;
        $display("STOP tests W=%0d H=%0d FIFO=32 seed=fedcba98",W,H);
        for(i=0;i<=8000000;i=i+1) mem[i]=8'ha5;
        for(i=0;i<4;i=i+1) blocked_stop(i);
        // Clearing CONTROL.ENABLE must drain exactly like STOP.
        setup();hold_b=1;
        fork
            feed(32);
            begin
                wait(pending);
                write_reg(8,1,1,1,0);
                status_read(status);
                if(status[2]) $fatal(1,"disable returned early IDLE");
                hold_b=0;wait_idle();
            end
        join
        $display("PASS CONTROL disable drains outstanding B");
        // STOP and source SOF at the same acceptance edge: no allocation/write.
        setup();saved_writes=writes;
        fork
            write_reg('h20,8,15,0,0);
            begin
                wait(dut.registers.stop_request);
                @(negedge clk);sv=1;ss=1;se=0;sd=32'h80408020;
                @(negedge clk);sv=0;ss=0;
            end
        join
        wait_idle();if(writes!=saved_writes) $fatal(1,"SOF raced past STOP");
        $display("PASS STOP wins simultaneous SOF");
        // A completed frame survives STOP; consuming it does not restart DMA.
        setup();feed(30);wait(irq);
        write_reg('h20,8,15,1,0);wait_idle();
        if(!irq) $fatal(1,"STOP discarded completed frame");
        result_check(0,0);compare_frame(30,4080);
        write_reg('h1c,0,15,0,0);write_reg('h20,4,15,1,0);
        feed(31);if(irq) $fatal(1,"disabled frame captured");
        $display("PASS completed-frame boundary retained, IDLE and continued disabled traffic");
        $finish;
    end
endmodule
