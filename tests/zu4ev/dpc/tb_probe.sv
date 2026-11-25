`timescale 1ns/1ps
module tb_probe;
    reg clk=0;
    always #5 clk=~clk;
    reg resetn=0, start=0, low=0, valid=0, sof=0, eol=0, fault=0;
    reg [9:0] threshold=512;
    reg [19:0] data=0;
    reg read_enable=0,read_lane=0;
    reg [9:0] read_index=0;
    wire [31:0] read_data,capture_seq;
    wire busy,done,overflow,failed;
    wire [10:0] count0,count1;
    dpc_probe #(.WIDTH(16),.HEIGHT(4),.CAPTURE_LIMIT(4)) dut (.*);

    task arm;
        @(negedge clk);start=1;
        @(negedge clk);start=0;
    endtask
    task send_frame(input integer mode);
        for(integer y=0;y<4;y=y+1) for(integer x=0;x<16;x=x+2) begin
            @(negedge clk);valid=1;sof=x==0&&y==0;eol=x==14;
            if(mode==1) data={10'd1023,10'd1023};
            else if(mode==2) data={(x==4 && y==2 ? 10'd0 : 10'd700),10'd700};
            else data={(x==2 ? 10'd512 : 10'd55),(x==8 ? 10'd700 : 10'd55)};
            if(x==6) begin
                @(negedge clk);valid=0;sof=0;eol=0;
            end
        end
        @(negedge clk);valid=0;sof=0;eol=0;
    endtask
    task check_word(input bit lane,input [9:0] idx,input [31:0] want);
        @(negedge clk);read_enable=1;read_lane=lane;read_index=idx;
        @(posedge clk);#1;if(read_data!==want)$fatal(1,"probe lane %d index%d got%h want%h",lane,idx,read_data,want);
        @(negedge clk);read_enable=0;
    endtask

    initial begin
        repeat(3)@(negedge clk);resetn=1;
        arm();send_frame(0);
        if(!done||busy||overflow||failed||count0!=4||count1!=4||capture_seq!=1)$fatal(1,"exact limit");
        for(integer n=0;n<4;n=n+1) begin
            check_word(0,n,n*2048+8);
            check_word(1,n,n*2048+3);
        end
        check_word(0,4,0);
        arm();send_frame(1);
        if(done||busy||!overflow||failed||capture_seq!=1)$fatal(1,"overflow was published");
        check_word(1,0,0);
        arm();@(negedge clk);valid=1;sof=1;eol=1;
        @(negedge clk);valid=0;sof=0;eol=0;
        if(done||busy||overflow||!failed||capture_seq!=1)$fatal(1,"bad frame was published");
        low=1;threshold=0;
        arm();send_frame(2);
        if(!done||busy||overflow||failed||count0!=0||count1!=1||capture_seq!=2)$fatal(1,"low recovery");
        check_word(1,0,2*2048+5);
        $display("DPC_PROBE_PASS lanes, exact capacity, overflow, malformed, recovery, low threshold");
        $finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
