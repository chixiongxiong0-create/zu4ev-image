`timescale 1ns/1ps
module tb;
reg clk=0; always #5 clk=~clk;
reg rst=0; wire cr,req,we; wire [31:0] addr,wd; wire [3:0] be; reg [31:0] rd=0; reg [31:0] mem=0;
reg [31:0] ar=0,aw=0, w=0; reg [3:0] st=15; reg arv=0,rr=0,awv=0,wv=0,br=0; wire arr,rv,awr,wr,bv; wire [31:0] data; wire [1:0] rp,bp;
ibex_small_loader d(.clk_i(clk),.rst_ni(rst),.cpu_rst_no(cr),.load_req_o(req),.load_we_o(we),.load_addr_o(addr),.load_wdata_o(wd),.load_be_o(be),.load_rdata_i(rd),.s_axi_araddr(ar),.s_axi_awaddr(aw),.s_axi_wdata(w),.s_axi_arprot(3'b0),.s_axi_awprot(3'b0),.s_axi_wstrb(st),.s_axi_arvalid(arv),.s_axi_rready(rr),.s_axi_awvalid(awv),.s_axi_wvalid(wv),.s_axi_bready(br),.s_axi_arready(arr),.s_axi_rvalid(rv),.s_axi_awready(awr),.s_axi_wready(wr),.s_axi_bvalid(bv),.s_axi_rdata(data),.s_axi_rresp(rp),.s_axi_bresp(bp));
always @(posedge clk) if(req) begin if(we) begin if(be[0]) mem[7:0]<=wd[7:0]; if(be[1]) mem[15:8]<=wd[15:8]; if(be[2]) mem[23:16]<=wd[23:16]; if(be[3]) mem[31:24]<=wd[31:24]; end else rd<=mem; end
task write(input [31:0] a,input [31:0] v,input [3:0] s,input [1:0] expected); begin
@(negedge clk); aw=a; awv=1; do @(posedge clk); while(!awr); @(negedge clk); awv=0; w=v; st=s; wv=1; do @(posedge clk); while(!wr); @(negedge clk); wv=0; wait(bv); if(bp!==expected) $fatal(1,"bad bresp"); repeat(2) @(negedge clk); if(!bv) $fatal(1,"bvalid dropped"); br=1; @(negedge clk); br=0; end endtask
task read(input [31:0] a,input [31:0] expected,input [1:0] er); begin @(negedge clk); ar=a; arv=1; do @(posedge clk); while(!arr); @(negedge clk); arv=0; wait(rv); if(rp!==er || data!==expected) $fatal(1,"bad read %h %h",data,rp); repeat(2) @(negedge clk); if(!rv || data!==expected) $fatal(1,"rvalid dropped"); rr=1; @(negedge clk); rr=0; end endtask
initial begin repeat(2) @(negedge clk); rst=1; if(cr) $fatal(1,"early release"); write('h100000,'h12345678,15,0); write('h100000,'h0000aa00,2,0); read('h100000,'h1234aa78,0); write(0,1,15,0); if(!cr) $fatal(1,"not running"); write('h100000,0,15,2); read('h100000,0,2); write(0,0,15,0); if(cr) $fatal(1,"not halted"); read('h100000,'h1234aa78,0); $display("LOADER_PASS"); $finish; end
initial begin #10000; $fatal(1,"timeout"); end
endmodule
