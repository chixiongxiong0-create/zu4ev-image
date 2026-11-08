`timescale 1ns/1ps
module tb_dpc;
    parameter W=128, H=128;
    reg clk=0;
    always #2.5 clk=~clk;
    reg resetn=0, sv=0, ss=0, se=0, sp=0, sf=0;
    reg [19:0] sd=0;
    wire [19:0] md;
    wire mv,ms,me,mp,mf;
    reg cw=0,cr=0;
    reg [15:0] wa=0,ra=0;
    reg [31:0] wd=0;
    wire [31:0] rd;
    wire ok;
    dpc_raw10 #(.WIDTH(W),.HEIGHT(H)) dut (
        .clk(clk),.resetn(resetn),.s_data(sd),.cal_data(sd),
        .s_valid(sv),.s_sof(ss),.s_eol(se),.s_packet_error(sp),.s_global_fault(sf),
        .cal_valid(sv),.cal_sof(ss),.cal_eol(se),.cal_fault(sp||sf),
        .m_data(md),.m_valid(mv),.m_sof(ms),.m_eol(me),.m_packet_error(mp),.m_global_fault(mf),
        .csr_write(cw),.csr_read(cr),.csr_waddr(wa),.csr_raddr(ra),.csr_wdata(wd),
        .csr_write_ok(ok),.csr_rdata(rd));

    reg [W-1:0] bad[0:1][0:H-1];
    reg [31:0] runs[0:1][0:1023];
    integer num_runs[0:1], repair_count[0:1];
    integer seed=32'hd9c01234;
    integer input_pairs=0, checked=0, seen_frames=0, xout=0, yout=0, seen_faults=0;
    integer selector[0:7];

    task add_run(input integer bank,y,x,n);
        runs[bank][num_runs[bank]]=(n-1)*2097152+y*2048+x;
        num_runs[bank]=num_runs[bank]+1;
        repair_count[bank]=repair_count[bank]+n;
        for(integer k=x;k<x+n;k=k+1) bad[bank][y][k]=1'b1;
    endtask

    function automatic integer pixel(input integer x,y,frame);
        if (x==W-9 && y==33) pixel=1023; // legitimate single-pixel highlight
        else if (x==W-12 && y==33) pixel=0;
        else if (bad[0][y][x] || bad[1][y][x]) pixel=((x^y)&1) ? 1023 : 0;
        else pixel=(97*x+131*y+23*frame+(x*y)%31)&1023;
    endfunction

    function automatic integer golden(input integer x,y,frame,bank);
        integer l,r,numerator,denominator;
        begin
            golden=pixel(x,y,frame);
            if (bank>=0 && bad[bank][y][x]) begin
                l=x-1;
                r=x+1;
                while(l>=0 && bad[bank][y][l]) l=l-1;
                while(r<W && bad[bank][y][r]) r=r+1;
                if(l<0) golden=pixel(r,y,frame);
                else if(r>=W) golden=pixel(l,y,frame);
                else begin
                    denominator=r-l;
                    numerator=pixel(l,y,frame)*(r-x)+pixel(r,y,frame)*(x-l);
                    golden=(numerator+denominator/2)/denominator;
                end
            end
        end
    endfunction

    always @(posedge clk) begin
        #1;
        if (resetn && mf) seen_faults=seen_faults+1;
        if (resetn && mv) begin
            if (ms !== (xout==0 && yout==0) || me !== (xout==W-2))
                $fatal(1,"marker frame %0d (%0d,%0d)",seen_frames,xout,yout);
            if (md[9:0] !== 10'(golden(xout,yout,seen_frames,selector[seen_frames])) ||
                md[19:10] !== 10'(golden(xout+1,yout,seen_frames,selector[seen_frames])))
                $fatal(1,"pixel frame%0d (%0d,%0d) got %h expected %0d/%0d",seen_frames,xout,yout,md,
                       golden(xout,yout,seen_frames,selector[seen_frames]),
                       golden(xout+1,yout,seen_frames,selector[seen_frames]));
            checked=checked+1;
            if (me) begin
                xout=0;
                if (yout==H-1) begin yout=0;seen_frames=seen_frames+1;end
                else yout=yout+1;
            end else xout=xout+2;
        end
    end

    task write_csr(input [15:0] a,input [31:0] v,input bit accepted);
        @(negedge clk);wa=a;wd=v;cw=1;
        #1;if(ok !== accepted)$fatal(1,"write %h value %h expected acceptance %d",a,v,accepted);
        @(negedge clk);cw=0;
    endtask
    task read_check(input [15:0] a,input [31:0] v);
        @(negedge clk);ra=a;cr=1;
        @(posedge clk);#2;if(rd!==v)$fatal(1,"read %h got %h want %h",a,rd,v);
        @(negedge clk);cr=0;
    endtask
    task upload(input integer bank);
        write_csr(16'h3110,num_runs[bank],1);
        for(integer n=0;n<num_runs[bank];n=n+1) begin
            write_csr(16'h8000+4*n,runs[bank][n],1);
            read_check(16'h8000+4*n,runs[bank][n]);
        end
    endtask

    task frame(input integer id,input bit bubbles);
        integer x,y;
        for(y=0;y<H;y=y+1) for(x=0;x<W;x=x+2) begin
            if (bubbles && ($random(seed)&7)==0) begin
                @(negedge clk);sv=0;ss=0;se=0;
            end
            @(negedge clk);sv=1;ss=(x==0&&y==0);se=(x==W-2);
            sd={10'(pixel(x+1,y,id)),10'(pixel(x,y,id))};
            input_pairs=input_pairs+1;
        end
    endtask
    task idle;
        @(negedge clk);sv=0;ss=0;se=0;
    endtask

    initial begin
        seed=32'hd9c01234;
        for(integer bank=0;bank<2;bank=bank+1) begin
            num_runs[bank]=0;repair_count[bank]=0;
            for(integer y=0;y<H;y=y+1) bad[bank][y]='0;
        end
        for(integer n=1;n<=32;n=n+1) add_run(0,n-1,17+(n%2),n);
        for(integer y=36;y<41;y=y+1) add_run(0,y,31,12);
        add_run(0,41,0,7);add_run(0,42,W-32,32);
        for(integer x=0;x<64;x=x+2) add_run(0,45,x,1);
        add_run(0,H-1,W-4,4);
        add_run(1,0,0,2);add_run(1,1,1,32);add_run(1,2,2,32);
        // Exercise the last entry, 1024-count representation and sustained
        // one-run-per-pair lookup through a dense but legal sparse map.
        for(integer y=4;num_runs[1]<1023;y=y+1)
            for(integer x=0;x<128 && num_runs[1]<1023;x=x+2) add_run(1,y,x,1);
        add_run(1,H-1,W-1,1);
        selector[0]=-1;selector[1]=0;selector[2]=1;selector[3]=-1;selector[4]=-1;
        repeat(5)@(negedge clk);resetn=1;
        read_check(16'h3100,32'h44504331);
        frame(0,1);idle();wait(seen_frames==1);
        read_check(16'h3124,0);
        write_csr(16'h3108,3,0);
        write_csr(16'h3110,2,1);
        write_csr(16'h8004,0,0);
        write_csr(16'h8000,32'hfc000000,0);
        write_csr(16'h8000,32'(W-1)|(1<<21),0);
        write_csr(16'h8000,0,1);
        write_csr(16'h8004,1,0); // touching runs must be merged
        write_csr(16'h3108,3,0);
        upload(0);write_csr(16'h3108,3,1);
        fork
            begin frame(1,1);frame(2,0);idle();end
            begin
                wait(input_pairs>W*H/2+W);
                upload(1);write_csr(16'h3108,3,1);
                write_csr(16'h3110,0,0); // pending table immutable
                wait(seen_frames==2);
                read_check(16'h3124,repair_count[0]);
            end
        join
        wait(seen_frames==3);
        read_check(16'h3124,repair_count[1]);
        read_check(16'h3114,2);
        read_check(16'h311c,1024);
        write_csr(16'h3108,2,1);
        @(negedge clk);sv=1;ss=1;se=1; // malformed first row
        idle();
        @(negedge clk);sf=1;
        @(negedge clk);sf=0;
        frame(3,1);idle();wait(seen_frames==4);
        read_check(16'h3124,0);
        if(seen_faults!=2)$fatal(1,"fault count %0d",seen_faults);
        @(negedge clk);sv=1;ss=1;se=0;
        idle();@(negedge clk);resetn=0;
        repeat(3)@(negedge clk);resetn=1;
        frame(4,0);idle();wait(seen_frames==5);
        repeat(20)@(negedge clk);
        if(checked!=5*W*H/2)$fatal(1,"pair count %0d",checked);
        $display("DPC_CORE_PASS %0dx%0d checked=%0d all lengths+cluster+banks seed=d9c01234",W,H,checked);
        $finish;
    end
    initial begin #1000000000;$fatal(1,"timeout");end
endmodule
