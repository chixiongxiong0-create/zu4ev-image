`timescale 1ns/1ps
// Two-pixel Mono RAW10 smooth-field correction; same-clock CSR extension.
module ffc_raw10 #(
    parameter integer WIDTH=1280, HEIGHT=1024, SHIFT=5, STATS_FRAMES=32
)(
    input wire clk, resetn,
    input wire [19:0] s_data,
    input wire s_valid,s_sof,s_eol,s_packet_error,s_global_fault,
    output wire [19:0] m_data,
    output wire m_valid,m_sof,m_eol,m_packet_error,m_global_fault,
    input wire csr_write,csr_read,
    input wire [15:0] csr_waddr,csr_raddr,
    input wire [31:0] csr_wdata,
    output wire csr_write_ok,
    output reg [31:0] csr_rdata
);
    localparam integer STEP=1<<SHIFT, COLS=WIDTH/STEP+1, ROWS=HEIGHT/STEP+1;
    localparam integer NODES=COLS*ROWS, CELLS=(COLS-1)*(ROWS-1);
    localparam integer NB=$clog2(NODES+1), AB=$clog2(2*NODES);
    reg active_bank, active_enable, pending, pending_enable;
    reg [9:0] shadow_pedestal,active_pedestal,pending_pedestal;
    reg [NB-1:0] uploaded;
    reg [31:0] apply_seq;
    reg [10:0] x,y;
    wire first_pair=s_valid && s_sof;
    wire commit=first_pair && pending;
    wire video_bank=active_bank ^ commit;
    wire video_enable=commit ? pending_enable : active_enable;
    wire [9:0] video_pedestal=commit ? pending_pedestal : active_pedestal;
    wire [10:0] px=s_sof ? 11'd0 : x;
    wire [10:0] py=s_sof ? 11'd0 : y;
    wire [NB-1:0] node_index=(py>>SHIFT)*COLS+(px>>SHIFT);
    wire [AB-1:0] base_index=(video_bank ? NODES : 0)+node_index;
    wire node_write=(csr_waddr>=16'h4000 && csr_waddr<16'h4000+4*NODES);
    wire [NB-1:0] write_node=(csr_waddr-16'h4000)>>2;
    wire [AB-1:0] write_index=(active_bank ? 0 : NODES)+write_node;
    wire stats_busy,stats_done,stats_failed;
    wire [31:0] stats_frames,stats_rdata;
    wire stats_start=csr_write && csr_write_ok && csr_waddr==16'h3040;
    wire stats_read=csr_read && csr_raddr>=16'h6000 && csr_raddr<16'h6000+4*CELLS;
    wire [10:0] stats_index=(csr_raddr-16'h6000)>>2;
    reg stats_read_d,node_read_d,stats_output;
    wire node_read=csr_read && csr_raddr>=16'h4000 && csr_raddr<16'h4000+4*NODES;
    wire [23:0] node_rdata;
    reg [31:0] regular_rdata;
    always @* begin
        csr_rdata=stats_read_d ? stats_rdata : node_read_d ? {8'd0,node_rdata} : regular_rdata;
    end
    assign csr_write_ok=csr_waddr[1:0]==0 && (
        (node_write && !pending && uploaded<NODES && write_node==uploaded &&
         csr_wdata[31:24]==0 && csr_wdata[23:10]!=0) ||
        (csr_waddr==16'h3010 && !pending && csr_wdata<=1023) ||
        (csr_waddr==16'h3008 && !pending &&
         (csr_wdata==2 || (csr_wdata==3 && uploaded==NODES))) ||
        (csr_waddr==16'h3040 && !stats_busy && csr_wdata==1) ||
        (csr_waddr==16'h3050 && !stats_busy && csr_wdata<=1));
    ffc_stats #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.SHIFT(SHIFT),.FRAMES(STATS_FRAMES)) statistics (
        .clk(clk),.resetn(resetn),.start(stats_start),.s_data(stats_output ? m_data : s_data),
        .s_valid(stats_output ? m_valid : s_valid),.s_sof(stats_output ? m_sof : s_sof),.s_eol(stats_output ? m_eol : s_eol),
        .s_fault(stats_output ? (m_packet_error|m_global_fault) : (s_packet_error|s_global_fault)),.read_enable(stats_read),
        .read_index(stats_index),.read_data(stats_rdata),.busy(stats_busy),
        .done(stats_done),.failed(stats_failed),.frames_done(stats_frames));
    // The CPU port writes all replicas. The video port never reads the inactive bank.
    wire [23:0] a0,b0,c0,d0;
    wire cpu_we=csr_write && csr_write_ok && node_write;
    wire [AB-1:0] cpu_addr=cpu_we ? write_index :
        (active_bank ? 0 : NODES)+((csr_raddr-16'h4000)>>2);
    wire video_read=s_valid && video_enable;
    ffc_dual_ram #(.WIDTH(24),.ADDR_BITS(AB)) map_a (
        .clk(clk),.a_enable(cpu_we || node_read),.a_write(cpu_we),
        .a_addr(cpu_addr),.a_data(csr_wdata[23:0]),.a_q(node_rdata),
        .b_enable(video_read),.b_addr(base_index),.b_q(a0));
    ffc_dual_ram #(.WIDTH(24),.ADDR_BITS(AB)) map_b (
        .clk(clk),.a_enable(cpu_we),.a_write(cpu_we),
        .a_addr(cpu_addr),.a_data(csr_wdata[23:0]),.a_q(),
        .b_enable(video_read),.b_addr(AB'(base_index+1)),.b_q(b0));
    ffc_dual_ram #(.WIDTH(24),.ADDR_BITS(AB)) map_c (
        .clk(clk),.a_enable(cpu_we),.a_write(cpu_we),
        .a_addr(cpu_addr),.a_data(csr_wdata[23:0]),.a_q(),
        .b_enable(video_read),.b_addr(AB'(base_index+COLS)),.b_q(c0));
    ffc_dual_ram #(.WIDTH(24),.ADDR_BITS(AB)) map_d (
        .clk(clk),.a_enable(cpu_we),.a_write(cpu_we),
        .a_addr(cpu_addr),.a_data(csr_wdata[23:0]),.a_q(),
        .b_enable(video_read),.b_addr(AB'(base_index+COLS+1)),.b_q(d0));
    always @(posedge clk) begin
        if(csr_read) begin
            if(csr_raddr>=16'h4000 && csr_raddr<16'h4000+4*NODES) begin
                regular_rdata<=0; // Synchronous RAM output is selected by node_read_d.
            end else begin
                case(csr_raddr)
                    16'h3000:regular_rdata<=32'h46464331;
                    16'h3004:regular_rdata<=32'h00010000;
                    16'h3008:regular_rdata<=0;
                    16'h300c:regular_rdata<={29'd0,active_bank,pending,active_enable};
                    16'h3010:regular_rdata<={22'd0,shadow_pedestal};
                    16'h3014:regular_rdata<=apply_seq;
                    16'h3018:regular_rdata<=uploaded;
                    16'h301c:regular_rdata<=(ROWS<<16)|COLS;
                    16'h3020:regular_rdata<=(HEIGHT<<16)|WIDTH;
                    16'h3024:regular_rdata<=STEP;
                    16'h3040:regular_rdata<=0;
                    16'h3044:regular_rdata<={29'd0,stats_failed,stats_done,stats_busy};
                    16'h3048:regular_rdata<=stats_frames;
                    16'h304c:regular_rdata<=STEP*STEP*STATS_FRAMES;
                    16'h3050:regular_rdata<={31'd0,stats_output};
                    default:regular_rdata<=0;
                endcase
            end
        end
    end
    always @(posedge clk) begin
        if(!resetn) begin
            active_bank<=0;active_enable<=0;pending<=0;pending_enable<=0;
            shadow_pedestal<=52;active_pedestal<=52;pending_pedestal<=52;
            uploaded<=0;apply_seq<=0;x<=0;y<=0;stats_read_d<=0;node_read_d<=0;stats_output<=0;
        end else begin
            stats_read_d<=stats_read;node_read_d<=node_read;
            if(csr_write && csr_write_ok) begin
                if(node_write) begin uploaded<=uploaded+1'b1;end
                if(csr_waddr==16'h3050) begin stats_output<=csr_wdata[0];end
                if(csr_waddr==16'h3010) begin shadow_pedestal<=csr_wdata[9:0];end
                if(csr_waddr==16'h3008) begin
                    pending<=1;pending_enable<=csr_wdata[0];pending_pedestal<=shadow_pedestal;
                end
            end
            if(commit) begin
                active_bank<=!active_bank;active_enable<=pending_enable;
                active_pedestal<=pending_pedestal;pending<=0;uploaded<=0;apply_seq<=apply_seq+1'b1;
            end
            if(s_valid) begin
                if(s_eol) begin
                    x<=0;y<=(py==HEIGHT-1) ? 11'd0 : py+1'b1;
                end else begin x<=px+11'd2;y<=py;end
            end
        end
    end
    // Arithmetic pipeline. Weights are bounded unsigned values, with one final
    // rounding after bilinear interpolation (no intermediate-axis truncation).
    reg [SHIFT:0] fx0,fy0,fx1;
    reg [SHIFT+14:0] gl1,gr1;
    reg [SHIFT+10:0] dl1,dr1;
    wire [SHIFT:0] wy0=STEP-fy0;
    wire [SHIFT:0] wx1=STEP-fx1;
    wire [2*SHIFT+14:0] gsum0=gl1*wx1+gr1*fx1+(1<<(2*SHIFT-1));
    wire [2*SHIFT+14:0] gsum1=gl1*(wx1-1'b1)+gr1*(fx1+1'b1)+(1<<(2*SHIFT-1));
    wire [2*SHIFT+10:0] dsum0=dl1*wx1+dr1*fx1+(1<<(2*SHIFT-1));
    wire [2*SHIFT+10:0] dsum1=dl1*(wx1-1'b1)+dr1*(fx1+1'b1)+(1<<(2*SHIFT-1));
    reg [13:0] gain2[0:1],gain3[0:1];
    reg [9:0] dark2[0:1],diff3[0:1];
    reg [23:0] product4[0:1];
    reg [9:0] result5[0:1];
    reg [19:0] raw_pipe[0:5];
    reg [9:0] pedestal_pipe[0:5];
    reg [5:0] valid_pipe,sof_pipe,eol_pipe,packet_pipe,fault_pipe,enable_pipe;
    wire [24:0] rounded0={1'b0,product4[0]}+25'd2048+({15'd0,pedestal_pipe[4]}<<12);
    wire [24:0] rounded1={1'b0,product4[1]}+25'd2048+({15'd0,pedestal_pipe[4]}<<12);
    integer i;
    always @(posedge clk) begin
        if(!resetn) begin
            valid_pipe<=0;sof_pipe<=0;eol_pipe<=0;packet_pipe<=0;fault_pipe<=0;enable_pipe<=0;
        end else begin
            valid_pipe<={valid_pipe[4:0],s_valid};
            sof_pipe<={sof_pipe[4:0],s_sof && s_valid};
            eol_pipe<={eol_pipe[4:0],s_eol && s_valid};
            packet_pipe<={packet_pipe[4:0],s_packet_error};
            fault_pipe<={fault_pipe[4:0],s_global_fault};
            enable_pipe<={enable_pipe[4:0],video_enable};
        end
        raw_pipe[0]<=s_data;pedestal_pipe[0]<=video_pedestal;
        for(i=1;i<6;i=i+1) begin
            raw_pipe[i]<=raw_pipe[i-1];pedestal_pipe[i]<=pedestal_pipe[i-1];
        end
        fx0<=px & (STEP-1);fy0<=py & (STEP-1);fx1<=fx0;
        gl1<=a0[23:10]*wy0+c0[23:10]*fy0;
        gr1<=b0[23:10]*wy0+d0[23:10]*fy0;
        dl1<=a0[9:0]*wy0+c0[9:0]*fy0;
        dr1<=b0[9:0]*wy0+d0[9:0]*fy0;
        gain2[0]<=gsum0>>(2*SHIFT);gain2[1]<=gsum1>>(2*SHIFT);
        dark2[0]<=dsum0>>(2*SHIFT);dark2[1]<=dsum1>>(2*SHIFT);
        for(i=0;i<2;i=i+1) begin
            diff3[i]<=raw_pipe[2][i*10+:10]>dark2[i] ? raw_pipe[2][i*10+:10]-dark2[i] : 10'd0;
            gain3[i]<=gain2[i];product4[i]<=diff3[i]*gain3[i];
        end
        result5[0]<=rounded0>25'd4190208 ? 10'd1023 : rounded0[21:12];
        result5[1]<=rounded1>25'd4190208 ? 10'd1023 : rounded1[21:12];
    end
    assign m_data=enable_pipe[5] ? {result5[1],result5[0]} : raw_pipe[5];
    assign m_valid=valid_pipe[5];assign m_sof=sof_pipe[5];assign m_eol=eol_pipe[5];
    assign m_packet_error=packet_pipe[5];assign m_global_fault=fault_pipe[5];
endmodule
