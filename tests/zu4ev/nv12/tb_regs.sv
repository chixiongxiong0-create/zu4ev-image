`timescale 1ns/1ps
module tb_regs;
    reg clk=0;always #5 clk=~clk;
    reg resetn=0;
    reg [7:0] awaddr=0,araddr=0;
    reg awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
    reg [31:0] wdata=0;
    reg [3:0] wstrb=0;
    wire awready,wready,bvalid,arready,rvalid;
    wire [1:0] bresp,rresp;
    wire [31:0] rdata;
    wire cv,cr,ce,le,fv,fr,rel,ie;
    wire [1:0] slot;
    wire [31:0] base,stride,fb,fs,ft,reltag,failed,db,ds,dt;
    wire dv,rr;
    reg dr=0,rv=0,re=0;
    reg [31:0] rt=0;
    nv12_axi_regs regs(
        .capture_enable(),.capture_idle(1'b1),.stop_request(),
        .clk(clk),.resetn(resetn),.s_axi_awaddr(awaddr),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
        .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
        .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
        .s_axi_araddr(araddr),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
        .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
        .cfg_valid(cv),.cfg_ready(cr),.cfg_error(ce),.release_error(le),.cfg_slot(slot),.cfg_base(base),.cfg_stride(stride),
        .frame_valid(fv),.frame_ready(fr),.frame_base(fb),.frame_stride(fs),.frame_tag(ft),
        .release_valid(rel),.release_tag(reltag),.irq_enable(ie),.dropped_frames(32'd9),.failed_frames(failed));
    nv12_buffer_pool #(.WIDTH(34),.HEIGHT(6)) pool(
        .clk(clk),.resetn(resetn),.cfg_valid(cv),.cfg_ready(cr),.cfg_slot(slot),.cfg_base(base),.cfg_stride(stride),
        .cfg_error(ce),.release_error(le),.desc_valid(dv),.desc_ready(dr),.desc_base(db),.desc_stride(ds),.desc_tag(dt),
        .result_valid(rv),.result_error(re),.result_tag(rt),.result_ready(rr),
        .frame_valid(fv),.frame_ready(fr),.frame_base(fb),.frame_stride(fs),.frame_tag(ft),
        .release_valid(rel),.release_tag(reltag),.failed_frames(failed));
    task write_reg(input [7:0] addr,input [31:0] value,input [3:0] mask,input integer order,input [1:0] expected);
        begin
            fork
                begin
                    repeat(order==0?1:4) @(negedge clk);
                    awaddr=addr;awvalid=1;
                    do @(posedge clk);while(!awready);
                    @(negedge clk);awvalid=0;
                end
                begin
                    repeat(order==0?4:1) @(negedge clk);
                    wdata=value;wstrb=mask;wvalid=1;
                    do @(posedge clk);while(!wready);
                    @(negedge clk);wvalid=0;
                end
            join
            wait(bvalid);@(negedge clk);
            repeat(3) begin
                if(!bvalid||bresp!==expected||awready||wready) $fatal(1,"bad B response %h = %h",addr,bresp);
                @(negedge clk);
            end
            bready=1;@(negedge clk);bready=0;
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
    initial begin
        repeat(3) @(negedge clk);resetn=1;
        read_reg(0,32'h4e563132,0);
        write_reg(8,1,1,0,0);read_reg(8,1,0);
        write_reg('h14,'h11223344,15,1,0);
        write_reg('h14,'h0000ab00,2,0,0);read_reg('h14,'h1122ab44,0);
        write_reg('h14,4096,15,1,0);write_reg('h18,64,15,0,0);
        write_reg('h20,1,15,1,0); // successful pool configuration
        write_reg('h20,1,15,0,2); // reserved slot cannot be reconfigured
        write_reg('h10,1,15,1,0);write_reg('h20,1,15,0,2); // overlap error pulse
        write_reg('h20,3,15,1,2);write_reg('h20,2,15,0,2); // bad command/no frame
        write_reg('h20,4,15,1,2); // release unused slot
        write_reg('h20,1,1,0,2);write_reg('h03,0,15,1,2);
        read_reg('h03,0,2);write_reg('h00,0,15,0,2);
        wait(dv);@(negedge clk);dr=1;
        @(negedge clk);dr=0;rv=1;rt=0;
        @(negedge clk);rv=0;
        wait(fv);read_reg('h24,4096,0);read_reg('h28,64,0);read_reg('h2c,0,0);
        write_reg('h20,2,15,0,0);if(fv) $fatal(1,"TAKE did not consume frame");
        write_reg('h1c,0,15,1,0);write_reg('h20,4,15,0,0);
        read_reg('h30,9,0);
        $display("PASS AXI-Lite AW/W ordering, strobes, B/R stalls, pool errors, metadata TAKE and RELEASE");$finish;
    end
    initial begin #40000;$fatal(1,"regs timeout");end
endmodule
