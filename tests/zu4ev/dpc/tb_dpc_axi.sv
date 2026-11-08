`timescale 1ns/1ps
module tb_dpc_axi;
    reg clk=0;
    always #5 clk=~clk;
    reg resetn=0;
    reg [15:0] aw=0,ar=0;
    reg [31:0] wd=0;
    reg [3:0] ws=15;
    reg av=0,wv=0,br=0,rv=0,rr=0;
    wire ardy,wrdy,rrdy,bv,rvalid;
    wire [1:0] bp,rp;
    wire [31:0] rd,md;
    reg sv=0,ss=0,se=0;
    reg [19:0] sd=0;
    wire mv,ms,me;
    isp_capture_frontend #(.USE_LTM(1),.WIDTH(64),.HEIGHT(64),.RUNTIME_CONFIG(1)) dut (
        .ibex_cfg_reset_ni(resetn),.isp_axi_awaddr(aw),.isp_axi_awvalid(av),.isp_axi_awready(ardy),
        .isp_axi_wdata(wd),.isp_axi_wstrb(ws),.isp_axi_wvalid(wv),.isp_axi_wready(wrdy),
        .isp_axi_bresp(bp),.isp_axi_bvalid(bv),.isp_axi_bready(br),
        .isp_axi_araddr(ar),.isp_axi_arvalid(rv),.isp_axi_arready(rrdy),
        .isp_axi_rdata(rd),.isp_axi_rresp(rp),.isp_axi_rvalid(rvalid),.isp_axi_rready(rr),
        .clk(clk),.resetn(resetn),.s_data(sd),.s_valid(sv),.s_sof(ss),.s_eol(se),
        .s_packet_error(1'b0),.s_global_fault(1'b0),.m_data(md),.m_valid(mv),.m_sof(ms),.m_eol(me));

    task write_bus(input [15:0] a,input [31:0] v,input [3:0] strb,input bit reverse,input [1:0] resp);
        if(reverse) begin
            @(negedge clk);wd=v;ws=strb;wv=1;
            do @(posedge clk);while(!wrdy);
            @(negedge clk);wv=0;repeat(2)@(negedge clk);aw=a;av=1;
            do @(posedge clk);while(!ardy);
            @(negedge clk);av=0;
        end else begin
            @(negedge clk);aw=a;av=1;
            do @(posedge clk);while(!ardy);
            @(negedge clk);av=0;repeat(2)@(negedge clk);wd=v;ws=strb;wv=1;
            do @(posedge clk);while(!wrdy);
            @(negedge clk);wv=0;
        end
        wait(bv);
        repeat(4) begin @(negedge clk);if(!bv||bp!==resp)$fatal(1,"B hold %h",a);end
        br=1;@(negedge clk);br=0;
    endtask

    task read_bus(input [15:0] a,input [31:0] expected,input [1:0] resp);
        @(negedge clk);ar=a;rv=1;
        do @(posedge clk);while(!rrdy);
        @(negedge clk);rv=0;ar=16'h3000; // address may change during synchronous R preparation
        wait(rvalid);
        repeat(4) begin
            @(negedge clk);
            if(!rvalid||rp!==resp||rd!==expected)$fatal(1,"R %h got%h/%h expected%h/%h",a,rd,rp,expected,resp);
        end
        rr=1;@(negedge clk);rr=0;
    endtask

    integer pairs=0,frames=0;
    always @(posedge clk) begin
        #1;
        if(resetn && mv) begin
            if(ms !== (pairs==0) || me !== (pairs%32==31))$fatal(1,"marker");
            if(md[19:0] !== (pairs==2 ? {10'd55,10'd1023} : {10'd55,10'd55}))
                $fatal(1,"unexpected RAW pixel pair %0d %h",pairs,md);
            pairs=pairs+1;
            if(pairs==2048) begin pairs=0;frames=frames+1;end
        end
    end
    task send_frame;
        for(integer y=0;y<64;y=y+1) for(integer x=0;x<64;x=x+2) begin
            @(negedge clk);sv=1;ss=x==0&&y==0;se=x==62;
            sd=(y==0&&x==0) ? {10'd1023,10'd1023} :
               (y==0&&x==4) ? {10'd55,10'd1023} : {10'd55,10'd55};
        end
        @(negedge clk);sv=0;ss=0;se=0;
    endtask

    initial begin
        repeat(4)@(negedge clk);resetn=1;
        read_bus(16'h3000,32'h46464331,0);
        read_bus(16'h3100,32'h44504331,0);
        read_bus(16'h3160,0,2);
        write_bus(16'h3110,1,1,0,2);
        write_bus(16'h3110,1,15,1,0);
        write_bus(16'h8000,1<<21,15,0,0);
        read_bus(16'h8000,1<<21,0);
        read_bus(16'h3000,32'h46464331,0);
        write_bus(16'h3108,3,15,1,0);
        read_bus(16'h310c,2,0);
        write_bus(16'h8000,0,15,0,2);
        write_bus(16'h3140,1023,15,1,0);
        write_bus(16'h3144,1,15,0,0);
        send_frame();wait(frames==1);
        read_bus(16'h310c,5,0);
        read_bus(16'h3124,2,0);
        read_bus(16'h3148,2,0);
        read_bus(16'h314c,2,0);
        read_bus(16'h3150,1,0);
        read_bus(16'ha004,4,0);
        read_bus(16'hb000,1,0);
        write_bus(16'h3140,(1<<17)|1023,15,1,0);
        write_bus(16'h3144,1,15,0,0);
        write_bus(16'h3140,0,15,0,2);
        send_frame();wait(frames==2);repeat(2)@(negedge clk);
        read_bus(16'h3148,2,0);
        read_bus(16'h314c,1,0);
        read_bus(16'h3150,0,0);
        read_bus(16'ha000,4,0);
        $display("DPC_AXI_PASS actual frontend, FFC/DPC mux, AW/W and stalls, probe source, bright point retained");
        $finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
