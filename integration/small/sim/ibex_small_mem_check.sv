`timescale 1ns/1ps
module ibex_small_mem_check(output logic done_o=0);
  logic clk=0, rst=0, ir=0, dr=0, we=0;
  logic [31:0] ia=0, da=0, wd=0;
  logic [3:0] be=0;
  wire ig, iv, ie, dg, dv, de;
  wire [31:0] id, dd;
  logic [31:0] aa=0, wa=0, ww=0;
  logic av=0, rr=0, wav=0, wv=0, br=0;
  wire ar, rv, war, wr, bv;
  wire [31:0] rd;
  wire [1:0] rp, bp;
  always #5 clk=~clk;
  ibex_small_mem #(.RomFile("selftest.mem"), .RamPrimitive("ultra")) m(
    .clk_i(clk),.rst_ni(rst),.instr_req_i(ir),.instr_addr_i(ia),
    .instr_gnt_o(ig),.instr_rvalid_o(iv),.instr_rdata_o(id),.instr_err_o(ie),
    .data_req_i(dr),.data_we_i(we),.data_be_i(be),.data_addr_i(da),.data_wdata_i(wd),
    .data_gnt_o(dg),.data_rvalid_o(dv),.data_rdata_o(dd),.data_err_o(de),
    .s_axi_araddr(aa), .s_axi_arprot(3'b0), .s_axi_arvalid(av),
    .s_axi_arready(ar), .s_axi_rvalid(rv), .s_axi_rready(rr), .s_axi_rdata(rd), .s_axi_rresp(rp),
    .s_axi_awaddr(wa), .s_axi_awprot(3'b0), .s_axi_awvalid(wav), .s_axi_awready(war),
    .s_axi_wdata(ww), .s_axi_wstrb(4'hf), .s_axi_wvalid(wv), .s_axi_wready(wr),
    .s_axi_bvalid(bv), .s_axi_bready(br), .s_axi_bresp(bp));
  task automatic axi_read(input logic[31:0] a, expected,input bit err);
    @(negedge clk); aa=a; av=1;
    do @(posedge clk); while(!ar);
    @(negedge clk); av=0;
    wait(rv); #1;
    if(rp !== (err ? 2'b10 : 2'b00) || rd !== expected) $fatal(1,"AXI read %h data=%h resp=%h",a,rd,rp);
    repeat(4) begin
      @(posedge clk); #1;
      if(ar || !rv || rd!==expected || rp!==(err ? 2'b10 : 2'b00)) $fatal(1,"AXI read unstable under backpressure");
    end
    @(negedge clk); rr=1;
    @(negedge clk); rr=0;
  endtask
  task automatic axi_write_reject(input bit data_first);
    @(negedge clk); wa=32'h00200000; ww=32'hdeadbeef;
    if(data_first) wv=1; else wav=1;
    @(negedge clk); wv=0; wav=0;
    repeat(3) @(negedge clk);
    if(data_first) wav=1; else wv=1;
    @(negedge clk); wv=0; wav=0;
    wait(bv);
    repeat(3) begin @(posedge clk); #1; if(!bv || bp!==2'b10) $fatal(1,"write rejection/backpressure"); end
    @(negedge clk); br=1;
    @(negedge clk); br=0;
  endtask
  task automatic data_access(input bit wr,input logic[31:0] a,w,input logic[3:0] mask,
                            input bit err,input logic[31:0] expected);
    @(negedge clk); dr=1; we=wr; da=a; wd=w; be=mask;
    #1; if(dg!==1) $fatal(1,"data grant");
    @(posedge clk); #1;
    if(dv!==1 || de!==err) $fatal(1,"data response addr=%h dv=%b de=%b ram=%b",a,dv,de,m.data_ram);
    if(!wr && !err && dd!==expected) $fatal(1,"data read %h got=%h expected=%h",a,dd,expected);
    @(negedge clk); dr=0;
    @(posedge clk); #1; if(dv!==0) $fatal(1,"extra response");
  endtask
  task automatic fetch(input logic[31:0] a,input bit err);
    @(negedge clk); ir=1; ia=a;
    @(posedge clk); #1;
    if(iv!==1 || ie!==err) $fatal(1,"instruction response %h",a);
    @(negedge clk); ir=0;
  endtask
  logic [31:0] expected;
  initial begin
    repeat(3) @(negedge clk); rst=1;
    fetch(32'h00100000,0); fetch(32'h0013fffc,0);
    fetch(32'h00140000,1); fetch(32'h000ffffc,1);
    data_access(1,32'h00200000,32'h12345678,15,0,0);
    data_access(0,32'h00200000,0,0,0,32'h12345678);
    data_access(1,32'h0023fffc,32'h89abcdef,15,0,0);
    data_access(0,32'h0023fffc,0,0,0,32'h89abcdef);
    for(int mask=0;mask<16;mask++) begin
      data_access(1,32'h00200100,32'h11223344,15,0,0);
      data_access(1,32'h00200100,32'haabbccdd,mask[3:0],0,0);
      expected=32'h11223344;
      for(int b=0;b<4;b++) if(mask[b]) expected[b*8+:8]=32'haabbccdd >> (b*8);
      data_access(0,32'h00200100,0,0,0,expected);
    end
    data_access(0,32'h0013fffc,0,0,0,0);
    data_access(1,32'h0013fffc,32'hffffffff,15,1,0);
    data_access(0,32'h0013fffc,0,0,0,0);
    data_access(0,32'h00240000,0,0,1,0);
    data_access(1,32'h001ffffc,1,15,1,0);
    @(negedge clk); rst=0; dr=1; ir=1;
    #1; if(dg!==0 || ig!==0 || dv!==0 || iv!==0) $fatal(1,"reset responses");
    @(negedge clk); dr=0; ir=0; rst=1;
    data_access(0,32'h00200000,0,0,0,32'h12345678);
    axi_read(32'h00200000,32'h12345678,0);
    axi_read(32'h0023fffc,32'h89abcdef,0);
    axi_read(32'h00240000,0,1); axi_read(32'h001ffffc,0,1);
    axi_read(32'h00200001,0,1);
    axi_write_reject(0); axi_write_reject(1);
    axi_read(32'h00200000,32'h12345678,0);
    // Different-word simultaneous CPU write and AXI read are supported.
    fork
      data_access(1,32'h00200200,32'habcdef12,15,0,0);
      axi_read(32'h00200000,32'h12345678,0);
    join
    // Same-word CPU write stalls AR, then B reads the committed word.
    @(negedge clk); dr=1; we=1; da=32'h00200000; wd=32'h76543210; be=15;
    aa=da; av=1; #1; if(ar!==0) $fatal(1,"same-address collision not blocked");
    @(posedge clk); @(negedge clk); dr=0; av=0;
    axi_read(32'h00200000,32'h76543210,0);
    $display("IBEX_AXI_PASS boundaries alignment backpressure write_reject concurrency collision");
    $display("IBEX_MEMORY_PASS all_16_byte_masks boundaries errors reset");
    done_o=1;
  end
endmodule

