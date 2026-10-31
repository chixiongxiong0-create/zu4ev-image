// SPDX-License-Identifier: Apache-2.0
// 256 KiB ROM (two synchronous read ports) + 256 KiB byte-write RAM.
module ibex_small_mem #(
  parameter RomFile = "",
  parameter RamPrimitive = "block",
  parameter ProgramPrimitive = "block",
  parameter int unsigned BootImageWords = 65536,
  parameter bit EnableInputMailbox = 1'b0,
  parameter bit EnableFirmwareLoader = 1'b0
) (
  input logic clk_i, rst_ni,
  input logic cpu_rst_ni,
  output logic memory_ready_o,
  input logic load_req_i, load_we_i,
  input logic [31:0] load_addr_i, load_wdata_i,
  input logic [3:0] load_be_i,
  output logic [31:0] load_rdata_o,
  input logic instr_req_i,
  input logic [31:0] instr_addr_i,
  output logic instr_gnt_o, instr_rvalid_o,
  output logic [31:0] instr_rdata_o,
  output logic instr_err_o,
  input logic data_req_i, data_we_i,
  input logic [3:0] data_be_i,
  input logic [31:0] data_addr_i, data_wdata_i,
  output logic data_gnt_o, data_rvalid_o,
  output logic [31:0] data_rdata_o,
  output logic data_err_o,
  input logic [31:0] s_axi_araddr, s_axi_awaddr, s_axi_wdata,
  input logic [2:0] s_axi_arprot, s_axi_awprot,
  input logic [3:0] s_axi_wstrb,
  input logic s_axi_arvalid, s_axi_rready, s_axi_awvalid, s_axi_wvalid, s_axi_bready,
  output logic s_axi_arready, s_axi_rvalid, s_axi_awready, s_axi_wready, s_axi_bvalid,
  output logic [31:0] s_axi_rdata,
  output logic [1:0] s_axi_rresp, s_axi_bresp
);
  wire cpu_reset_n = memory_ready_o && (EnableFirmwareLoader ? cpu_rst_ni : rst_ni);
  wire loader_access = EnableFirmwareLoader && rst_ni && !cpu_reset_n && load_req_i &&
      load_addr_i[31:18] == (32'h00100000 >> 18) && load_addr_i[1:0] == 0;
  // Port A is shared by instruction fetch and the halted firmware loader.
  wire rom_port_a_enable = loader_access || (instr_gnt_o && instr_rom);
  wire [15:0] rom_port_a_addr = loader_access ? load_addr_i[17:2] : instr_addr_i[17:2];
  logic [31:0] instr_word, rom_word, ram_word;
  assign load_rdata_o = instr_word;
  logic data_rom_q;
  wire instr_rom = instr_addr_i[31:18] == (32'h00100000 >> 18);
  wire data_rom = data_addr_i[31:18] == (32'h00100000 >> 18);
  wire data_ram = data_addr_i[31:18] == (32'h00200000 >> 18);
  logic [31:0] axi_ram_word;
  logic axi_pending, axi_error_q, aw_seen, w_seen;
  logic [31:0] awaddr_q, wdata_q;
  logic [3:0] wstrb_q;
  // Host writes are restricted to the input half of the final 4 KiB mailbox.
  // CPU owns output half; all other host writes still return SLVERR.
  wire write_legal = EnableInputMailbox && awaddr_q[31:11] == (32'h0023f000 >> 11)
                     && awaddr_q[1:0] == 0;
  wire write_collision = data_gnt_o && data_ram &&
                         data_addr_i[17:2] == awaddr_q[17:2];
  wire write_pair = aw_seen && w_seen && !s_axi_bvalid;
  wire write_exec = rst_ni && write_pair && !(write_legal && write_collision);
  wire write_ram = write_exec && write_legal;
  wire axi_legal = s_axi_araddr[31:18] == (32'h00200000 >> 18) && s_axi_araddr[1:0] == 0;
  wire collision = data_gnt_o && data_ram && data_we_i &&
                   data_addr_i[17:2] == s_axi_araddr[17:2];
  wire axi_accept = s_axi_arvalid && s_axi_arready;
  assign s_axi_arready = rst_ni && !axi_pending && !s_axi_rvalid && !collision && !write_pair;
  assign s_axi_awready = rst_ni && !aw_seen && !s_axi_bvalid;
  assign s_axi_wready = rst_ni && !w_seen && !s_axi_bvalid;

  xpm_memory_tdpram #(
    .MEMORY_SIZE(2097152), .MEMORY_PRIMITIVE(RamPrimitive), .CLOCKING_MODE("common_clock"),
    .ADDR_WIDTH_A(16), .ADDR_WIDTH_B(16), .READ_DATA_WIDTH_A(32), .READ_DATA_WIDTH_B(32),
    .WRITE_DATA_WIDTH_A(32), .WRITE_DATA_WIDTH_B(32),
    .BYTE_WRITE_WIDTH_A(8), .BYTE_WRITE_WIDTH_B(8),
    .READ_LATENCY_A(1), .READ_LATENCY_B(1),
    .WRITE_MODE_A(RamPrimitive == "ultra" ? "no_change" : "read_first"),
    .WRITE_MODE_B(RamPrimitive == "ultra" ? "no_change" : "read_first"),
    .USE_MEM_INIT(0), .SIM_ASSERT_CHK(1)
  ) u_ram (
    .clka(clk_i), .clkb(clk_i), .rsta(!rst_ni), .rstb(!rst_ni),
    .ena(data_gnt_o && data_ram), .enb((axi_accept && axi_legal) || write_ram),
    .addra(data_addr_i[17:2]), .addrb(write_ram ? awaddr_q[17:2] : s_axi_araddr[17:2]),
    .dina(data_wdata_i), .dinb(wdata_q),
    .wea(data_be_i & {4{data_we_i}}), .web(wstrb_q & {4{write_ram}}),
    .douta(ram_word), .doutb(axi_ram_word),
    .regcea(1'b1), .regceb(1'b1), .sleep(1'b0),
    .injectsbiterra(1'b0), .injectdbiterra(1'b0),
    .injectsbiterrb(1'b0), .injectdbiterrb(1'b0),
    .sbiterra(), .dbiterra(), .sbiterrb(), .dbiterrb()
  );
  // One outstanding read. Capture the synchronous B output one cycle after AR.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      axi_pending<=0; axi_error_q<=0; s_axi_rvalid<=0;
      s_axi_rdata<=0; s_axi_rresp<=0; aw_seen<=0; w_seen<=0; s_axi_bvalid<=0;
      awaddr_q<=0; wdata_q<=0; wstrb_q<=0; s_axi_bresp<=2'b10;
    end else begin
      if (s_axi_rvalid && s_axi_rready) s_axi_rvalid<=0;
      axi_pending<=axi_accept;
      if (axi_accept) axi_error_q<=!axi_legal;
      if (axi_pending) begin
        s_axi_rvalid<=1;
        s_axi_rdata<=axi_error_q ? 32'b0 : axi_ram_word;
        s_axi_rresp<=axi_error_q ? 2'b10 : 2'b00;
      end
      if (s_axi_awvalid && s_axi_awready) begin aw_seen<=1; awaddr_q<=s_axi_awaddr; end
      if (s_axi_wvalid && s_axi_wready) begin w_seen<=1; wdata_q<=s_axi_wdata; wstrb_q<=s_axi_wstrb; end
      if (write_exec) begin
        aw_seen<=0; w_seen<=0; s_axi_bvalid<=1; s_axi_bresp<=write_legal ? 2'b00 : 2'b10;
      end
      if (s_axi_bvalid && s_axi_bready) s_axi_bvalid<=0;
    end
  end

  generate
    if (ProgramPrimitive == "ultra") begin : gen_program_ultra
      // UltraRAM has no configuration-time INIT contents. A compact initialized
      // BRAM image is copied before either the CPU or its loader can run.
      // READ primes the synchronous boot ROM; WRITE commits that word to URAM.
      // Every runtime word is written, with zero padding beyond the image.
      (* rom_style = "block" *) logic [31:0] boot_rom [0:BootImageWords-1];
      logic [31:0] boot_word;
      logic [15:0] boot_addr;
      logic boot_write, boot_done;
      wire boot_busy = !boot_done;
      initial begin
        if (BootImageWords < 1 || BootImageWords > 65536)
          $fatal(1, "BootImageWords must be between 1 and 65536");
        if (RomFile != "") $readmemh(RomFile, boot_rom, 0, BootImageWords-1);
      end
      always_ff @(posedge clk_i) begin
        if (boot_busy && !boot_write) begin
          if ({1'b0, boot_addr} < BootImageWords && RomFile != "")
            boot_word <= boot_rom[boot_addr];
          else boot_word <= 32'b0;
        end
      end
      always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
          boot_addr <= '0;
          boot_write <= 1'b0;
          boot_done <= 1'b0;
        end else if (!boot_done) begin
          boot_write <= !boot_write;
          if (boot_write) begin
            if (boot_addr == 16'hffff) boot_done <= 1'b1;
            else boot_addr <= boot_addr + 16'd1;
          end
        end
      end
      assign memory_ready_o = boot_done && rst_ni;
      xpm_memory_tdpram #(
        .MEMORY_SIZE(2097152), .MEMORY_PRIMITIVE("ultra"), .CLOCKING_MODE("common_clock"),
        .ADDR_WIDTH_A(16), .ADDR_WIDTH_B(16), .READ_DATA_WIDTH_A(32), .READ_DATA_WIDTH_B(32),
        .WRITE_DATA_WIDTH_A(32), .WRITE_DATA_WIDTH_B(32),
        .BYTE_WRITE_WIDTH_A(8), .BYTE_WRITE_WIDTH_B(8),
        .READ_LATENCY_A(1), .READ_LATENCY_B(1),
        .WRITE_MODE_A("no_change"), .WRITE_MODE_B("no_change"),
        .USE_MEM_INIT(0), .SIM_ASSERT_CHK(1)
      ) u_program (
        .clka(clk_i), .clkb(clk_i), .rsta(!rst_ni), .rstb(!rst_ni),
        .ena((boot_busy && boot_write && rst_ni) || (!boot_busy && rom_port_a_enable)),
        .enb(data_gnt_o && data_rom && !data_we_i),
        .addra(boot_busy ? boot_addr : rom_port_a_addr), .addrb(data_addr_i[17:2]),
        .dina(boot_busy ? boot_word : load_wdata_i), .dinb(32'b0),
        .wea(boot_busy ? {4{boot_write && rst_ni}} : (load_be_i & {4{loader_access && load_we_i}})),
        .web(4'b0), .douta(instr_word), .doutb(rom_word),
        .regcea(1'b1), .regceb(1'b1), .sleep(1'b0),
        .injectsbiterra(1'b0), .injectdbiterra(1'b0),
        .injectsbiterrb(1'b0), .injectdbiterrb(1'b0),
        .sbiterra(), .dbiterra(), .sbiterrb(), .dbiterrb()
      );
    end else begin : gen_program_block
      (* rom_style = "block" *) logic [31:0] rom [0:65535];
      assign memory_ready_o = rst_ni;
      initial if (RomFile != "") $readmemh(RomFile, rom);
      always_ff @(posedge clk_i) begin
        if (rom_port_a_enable) begin
          if (loader_access && load_we_i) begin
            for (int lane = 0; lane < 4; lane++) begin
              if (load_be_i[lane])
                rom[rom_port_a_addr][lane*8 +: 8] <= load_wdata_i[lane*8 +: 8];
            end
          end
          instr_word <= rom[rom_port_a_addr];
        end
        if (data_gnt_o && data_rom && !data_we_i) rom_word <= rom[data_addr_i[17:2]];
      end
    end
  endgenerate
  assign instr_gnt_o = instr_req_i && cpu_reset_n;
  assign data_gnt_o = data_req_i && cpu_reset_n;
  assign instr_rdata_o = instr_word;
  assign data_rdata_o = data_rom_q ? rom_word : ram_word;
  always_ff @(posedge clk_i or negedge cpu_reset_n) begin
    if (!cpu_reset_n) begin
      instr_rvalid_o <= 0;
      instr_err_o <= 0;
      data_rvalid_o <= 0;
      data_err_o <= 0;
      data_rom_q <= 0;

    end else begin
      instr_rvalid_o <= instr_gnt_o;
      instr_err_o <= instr_gnt_o && !instr_rom;
      data_rvalid_o <= data_gnt_o;
      data_err_o <= data_gnt_o && !(data_ram || (data_rom && !data_we_i));
      if (data_gnt_o) data_rom_q <= data_rom;
    end
  end
endmodule
