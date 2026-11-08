`timescale 1ns/1ps
module tb_pool;
    reg clk=0;always #5 clk=~clk;
    reg resetn=0,cv=0,dr=0,rv=0,re=0,fr=0,release_valid=0;
    reg [1:0] slot=0;
    reg [31:0] base=0,stride=64,rt=0,release_tag=0;
    wire cr,ce,le,dv,rr,fv;
    wire [31:0] db,ds,dt,fb,fs,ft,failed;
    integer first,second;
    nv12_buffer_pool #(.WIDTH(34),.HEIGHT(6)) dut(
        .clk(clk),.resetn(resetn),.cfg_valid(cv),.cfg_ready(cr),.cfg_slot(slot),
        .cfg_base(base),.cfg_stride(stride),.cfg_error(ce),.release_error(le),
        .desc_valid(dv),.desc_ready(dr),.desc_base(db),.desc_stride(ds),.desc_tag(dt),
        .result_valid(rv),.result_error(re),.result_tag(rt),.result_ready(rr),
        .frame_valid(fv),.frame_ready(fr),.frame_base(fb),.frame_stride(fs),.frame_tag(ft),
        .release_valid(release_valid),.release_tag(release_tag),.failed_frames(failed));
    task configure_slot(input integer n,input integer addr,input integer err);
        begin
            @(negedge clk);cv=1;slot=n;base=addr;
            do @(posedge clk);while(!cr);
            @(negedge clk);cv=0;if(ce!==err[0]) $fatal(1,"configuration validation");
        end
    endtask
    task take(output integer t);
        begin
            wait(dv);@(negedge clk);t=dt;dr=1;
            @(negedge clk);dr=0;
        end
    endtask
    task finish_frame(input integer t,input integer err);
        begin
            @(negedge clk);rt=t;rv=1;re=err;
            @(negedge clk);rv=0;
        end
    endtask
    task consume(input integer t);
        reg [95:0] saved;
        begin
            wait(fv);@(negedge clk);saved={fb,fs,ft};
            repeat(5) begin @(negedge clk);if(!fv||{fb,fs,ft}!==saved) $fatal(1,"unstable consumer offer");end
            if(ft!==t) $fatal(1,"wrong frame");
            fr=1;@(negedge clk);fr=0;
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);resetn=1;
        configure_slot(0,4096,0);configure_slot(1,8192,0);configure_slot(2,4096,1);
        take(first);finish_frame(first,0);consume(first);
        take(second);if(first==second) $fatal(1,"overwrote held buffer");
        finish_frame(second,0);consume(second);
        repeat(8) begin @(negedge clk);if(dv) $fatal(1,"allocated held buffer");end
        release_tag=first;release_valid=1;
        @(negedge clk);release_valid=0;
        wait(dv);@(negedge clk);
        if(dt!==first) $fatal(1,"wrong recycled slot");
        repeat(5) begin @(negedge clk);if(!dv||dt!==first||db!==4096) $fatal(1,"unstable descriptor");end
        take(first);finish_frame(first,1);
        repeat(3) @(negedge clk);if(failed!=1||fv) $fatal(1,"error frame exposed");
        wait(dv);if(dt!==first) $fatal(1,"failed buffer not recycled");
        release_tag=99;release_valid=1;@(negedge clk);
        if(!le) $fatal(1,"bad release not rejected");
        release_valid=0;
        // Hold an offer while later completions wrap slot indices.
        @(negedge clk);resetn=0;repeat(3) @(negedge clk);resetn=1;
        configure_slot(0,4096,0);configure_slot(1,8192,0);
        configure_slot(2,12288,0);configure_slot(3,16384,0);
        take(first);take(second);take(first);take(second);
        finish_frame(1,0);repeat(4) @(negedge clk);
        finish_frame(2,0);finish_frame(3,0);finish_frame(0,0);
        consume(1);consume(2);consume(3);consume(0);
        $display("PASS completion FIFO preserves order across slot wrap with consumer backpressure");
        $display("PASS buffer pool rotation, held ownership, stalled offers, overlap rejection, failed recycle, invalid release");$finish;
    end
    initial begin #20000;$fatal(1,"pool timeout");end
endmodule
