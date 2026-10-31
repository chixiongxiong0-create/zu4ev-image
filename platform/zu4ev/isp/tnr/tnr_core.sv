`timescale 1ns/1ps
// Buffered YUY2 temporal filter. All memory transactions retire before recovery.
module tnr_core #(
    parameter integer WIDTH=1280, HEIGHT=1024,
    parameter integer FIFO_DEPTH=16384, CHUNK_WORDS=256
)(
    input wire clk, resetn,
    input wire cfg_enable, cfg_pending, cfg_clear_history,
    input wire [8:0] cfg_alpha,
    input wire [7:0] cfg_motion_lo, cfg_motion_hi,
    input wire mem_ready,
    output wire cfg_safe,
    input wire [31:0] s_data,
    input wire s_valid,s_sof,s_eol,s_fault,
    output wire s_ready,
    output reg [31:0] m_data,
    output reg m_valid,m_sof,m_eol,m_fault,
    input wire m_ready,
    output reg history_valid,
    output wire busy,
    output reg frame_done,
    output reg [31:0] frame_count,motion_count,filtered_count,fault_count,ddr_error_count,
    output wire [15:0] fifo_level,
    output wire [31:0] m_axi_awaddr,
    output wire [7:0] m_axi_awlen,
    output reg m_axi_awvalid,
    input wire m_axi_awready,
    output wire [127:0] m_axi_wdata,
    output wire [15:0] m_axi_wstrb,
    output wire m_axi_wlast,
    output reg m_axi_wvalid,
    input wire m_axi_wready,
    input wire [1:0] m_axi_bresp,
    input wire m_axi_bvalid,
    output wire m_axi_bready,
    output wire [31:0] m_axi_araddr,
    output wire [7:0] m_axi_arlen,
    output wire m_axi_arvalid,
    input wire m_axi_arready,
    input wire [127:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,
    input wire m_axi_rlast,m_axi_rvalid,
    output wire m_axi_rready
);
    localparam integer FP=$clog2(FIFO_DEPTH);
    localparam integer FRAME_WORDS=WIDTH*HEIGHT/2;
    localparam integer LINE_WORDS=WIDTH/2;
    localparam [3:0] IDLE=0,LUT_INIT=1,LUT_DIV=2,READ_ADDR=3,
        READ_DATA=4,PROCESS=5,WRITE_DATA=6,WRITE_RESP=7,BYPASS=8;
    reg [3:0] state;
    reg abort_frame, frame_memory, use_history, read_bank;
    reg [31:0] frame_word,chunk_offset;
    reg [15:0] line_word;
    reg [7:0] chunk_word;
    reg [5:0] read_beat,write_beat;
    reg [8:0] issued_words;
    reg p0_valid,p1_valid,p2_valid;
    reg [31:0] p0_current,p1_current,p2_data;
    reg [15:0] p0_old,p1_old;
    reg [7:0] p0_d0,p0_d1;
    reg [8:0] p1_w0,p1_w1;
    reg [1:0] p0_flags,p1_flags,p2_flags,p1_motion,p2_motion;
    reg [8:0] alpha;
    reg [7:0] lo,hi;
    reg [127:0] previous [0:63];
    reg [127:0] result [0:63];
    reg [8:0] weights [0:255];
    reg [7:0] lut_index,denominator;
    reg [16:0] quotient;
    reg [8:0] remainder;
    reg [4:0] divide_steps;
    wire [9:0] trial={remainder,quotient[16]};

    // The IP is simple dual-port RAM, common clock, 34x16384, read latency 1.
    // Two elastic head slots account for both the registered RAM output and
    // the in-flight read; simultaneous arrival/pop never drops a FIFO word.
    reg [FP-1:0] wr_ptr,rd_ptr;
    reg [FP:0] ram_count;
    reg [1:0] head_count;
    reg read_pending;
    reg [33:0] head0,head1;
    wire [33:0] ram_dout;
    wire output_room=!m_valid || m_ready;
    wire head_valid=head_count!=0;
    wire head_sof=head0[33],head_eol=head0[32];
    wire [31:0] current=head0[31:0];
    wire at_pixel=(state==PROCESS || state==BYPASS);
    wire p2_ready=!p2_valid || (at_pixel && output_room && !abort_frame);
    wire p1_ready=!p1_valid || p2_ready;
    wire p0_ready=!p0_valid || p1_ready;
    wire consume_pixel=at_pixel && p2_valid && output_room && !abort_frame;
    wire geometry_bad=(p2_flags[1] != (frame_word==0)) ||
                          (p2_flags[0] != (line_word==LINE_WORDS-1));
    wire pop_head=head_valid && ((state==IDLE && !head_sof) ||
                      (at_pixel && p0_ready && !abort_frame && issued_words<256));
    assign fifo_level=ram_count+head_count+read_pending;
    assign s_ready=(fifo_level<FIFO_DEPTH);
    wire overflow=s_valid && !s_ready;
    wire source_error=s_fault || overflow;
    wire pixel_error=consume_pixel && geometry_bad;
    wire fault_event=source_error || pixel_error;
    wire push_ram=s_valid && s_ready && !fault_event;
    wire issue_read=(ram_count!=0) &&
        ((head_count+read_pending-(pop_head ? 1:0))<2) && !fault_event;
    tnr_stream_bram stream_storage (
        .clka(clk),.ena(push_ram),.wea(push_ram),.addra(wr_ptr),
        .dina({s_sof,s_eol,s_data}),.clkb(clk),.enb(issue_read),
        .addrb(rd_ptr),.doutb(ram_dout)
    );
    always @(posedge clk) begin
        if(!resetn || fault_event) begin
            wr_ptr<=0; rd_ptr<=0; ram_count<=0;
            head_count<=0; read_pending<=0; head0<=0; head1<=0;
        end else begin
            if(push_ram) wr_ptr <= wr_ptr==FIFO_DEPTH-1 ? 0:wr_ptr+1'b1;
            if(issue_read) rd_ptr <= rd_ptr==FIFO_DEPTH-1 ? 0:rd_ptr+1'b1;
            case({push_ram,issue_read})
                2'b10: ram_count<=ram_count+1'b1;
                2'b01: ram_count<=ram_count-1'b1;
                default: ;
            endcase
            read_pending<=issue_read;
            case({read_pending,pop_head})
                2'b10: begin
                    if(head_count==0) head0<=ram_dout;
                    else head1<=ram_dout;
                    head_count<=head_count+1'b1;
                end
                2'b01: begin head0<=head1; head_count<=head_count-1'b1; end
                2'b11: begin
                    if(head_count==1) head0<=ram_dout;
                    else begin head0<=head1; head1<=ram_dout; end
                end
                default: ;
            endcase
        end
    end

    wire [31:0] old_word=previous[issued_words[7:2]][issued_words[1:0]*32 +:32];
    wire [7:0] d0=current[7:0]>=old_word[7:0] ?
                current[7:0]-old_word[7:0]:old_word[7:0]-current[7:0];
    wire [7:0] d1=current[23:16]>=old_word[23:16] ?
                current[23:16]-old_word[23:16]:old_word[23:16]-current[23:16];
    wire [17:0] blend0=p1_current[7:0]*(9'd256-p1_w0)+p1_old[7:0]*p1_w0+18'd128;
    wire [17:0] blend1=p1_current[23:16]*(9'd256-p1_w1)+p1_old[15:8]*p1_w1+18'd128;
    always @(posedge clk) begin
        if(!resetn || fault_event || abort_frame || state==IDLE) begin
            p0_valid<=0; p1_valid<=0; p2_valid<=0; issued_words<=0;
        end else begin
            if(state==WRITE_RESP && m_axi_bvalid) issued_words<=0;
            // Bypass also uses bounded chunks so the same issue limit applies.
            if(state==BYPASS && consume_pixel && chunk_word==255) issued_words<=0;
            if(p2_ready) begin
                p2_valid<=p1_valid;
                if(p1_valid) begin
                    p2_data<=use_history ?
                       {p1_current[31:24],blend1[15:8],p1_current[15:8],blend0[15:8]}:p1_current;
                    p2_flags<=p1_flags; p2_motion<=p1_motion;
                end
            end
            if(p1_ready) begin
                p1_valid<=p0_valid;
                if(p0_valid) begin
                    p1_current<=p0_current; p1_old<=p0_old; p1_flags<=p0_flags;
                    p1_w0<=weights[p0_d0]; p1_w1<=weights[p0_d1];
                    p1_motion<={p0_d1>=hi,p0_d0>=hi};
                end
            end
            if(p0_ready) begin
                p0_valid<=pop_head;
                if(pop_head) begin
                    issued_words<=issued_words+1'b1;
                    p0_current<=current; p0_old<={old_word[23:16],old_word[7:0]};
                    p0_d0<=d0; p0_d1<=d1; p0_flags<={head_sof,head_eol};
                end
            end
        end
    end
    assign cfg_safe=(state==IDLE) && !abort_frame && !m_valid;
    assign busy=(state!=IDLE) || m_valid;
    assign m_axi_awaddr=(read_bank ? 32'h00000000:32'h00400000)+chunk_offset;
    assign m_axi_araddr=(read_bank ? 32'h00400000:32'h00000000)+chunk_offset;
    assign m_axi_awlen=8'd63;
    assign m_axi_arlen=8'd63;
    assign m_axi_wdata=result[write_beat];
    assign m_axi_wstrb=16'hffff;
    assign m_axi_wlast=(write_beat==63);
    assign m_axi_arvalid=(state==READ_ADDR);
    assign m_axi_rready=(state==READ_DATA);
    assign m_axi_bready=(state==WRITE_RESP);

    always @(posedge clk) begin
        if(!resetn) begin
            state<=IDLE; abort_frame<=0; frame_memory<=0; use_history<=0;
            read_bank<=0; history_valid<=0;
            frame_word<=0; chunk_offset<=0; line_word<=0; chunk_word<=0;
            read_beat<=0; write_beat<=0;
            alpha<=192; lo<=6; hi<=20; lut_index<=0; denominator<=14;
            quotient<=0; remainder<=0; divide_steps<=0;
            m_axi_awvalid<=0; m_axi_wvalid<=0;
            m_data<=0; m_valid<=0; m_sof<=0; m_eol<=0; m_fault<=0;
            frame_done<=0; frame_count<=0; motion_count<=0;
            filtered_count<=0; fault_count<=0; ddr_error_count<=0;
        end else begin
            frame_done<=0;
            if(m_valid && m_ready) m_valid<=0;
            if(cfg_clear_history) history_valid<=0;
            case(state)
                IDLE: begin
                    abort_frame<=0;
                    if(head_valid && head_sof && output_room && !cfg_pending &&
                       !cfg_clear_history && !source_error && !abort_frame) begin
                        m_fault<=0;
                        frame_word<=0; line_word<=0; chunk_word<=0; chunk_offset<=0;
                        alpha<=cfg_alpha; lo<=cfg_motion_lo; hi<=cfg_motion_hi;
                        denominator<=cfg_motion_hi-cfg_motion_lo;
                        frame_memory<=cfg_enable && mem_ready;
                        use_history<=history_valid && cfg_enable && mem_ready;
                        if(cfg_enable && mem_ready) begin lut_index<=0; state<=LUT_INIT; end
                        else begin history_valid<=0; state<=BYPASS; end
                    end
                end
                LUT_INIT: begin
                    if(abort_frame) state<=IDLE;
                    else if(lut_index<=lo || lut_index>=hi) begin
                        weights[lut_index]<=lut_index<=lo ? alpha:9'd0;
                        if(lut_index==255) begin
                            if(use_history) state<=READ_ADDR; else state<=PROCESS;
                        end else lut_index<=lut_index+1'b1;
                    end else begin
                        quotient<=alpha*(hi-lut_index); remainder<=0;
                        divide_steps<=17; state<=LUT_DIV;
                    end
                end
                LUT_DIV: begin
                    if(abort_frame) state<=IDLE;
                    else begin
                        if(trial>={2'b00,denominator}) begin
                            remainder<=trial-denominator;
                            quotient<={quotient[15:0],1'b1};
                        end else begin
                            remainder<=trial[8:0]; quotient<={quotient[15:0],1'b0};
                        end
                        divide_steps<=divide_steps-1'b1;
                        if(divide_steps==1) begin
                            weights[lut_index]<={quotient[7:0],trial>={2'b00,denominator}};
                            lut_index<=lut_index+1'b1; state<=LUT_INIT;
                        end
                    end
                end
                READ_ADDR: if(m_axi_arready) begin read_beat<=0; state<=READ_DATA; end
                READ_DATA: if(m_axi_rvalid) begin
                    previous[read_beat]<=m_axi_rdata;
                    if(m_axi_rresp!=0 || (m_axi_rlast!=(read_beat==63))) begin
                        abort_frame<=1; history_valid<=0; m_fault<=1;
                        ddr_error_count<=ddr_error_count+1'b1;
                        fault_count<=fault_count+1'b1;
                    end
                    if(m_axi_rlast) begin
                        if(abort_frame || m_axi_rresp!=0 || read_beat!=63 || fault_event)
                            state<=IDLE;
                        else state<=PROCESS;
                    end else if(read_beat!=63) read_beat<=read_beat+1'b1;
                end
                PROCESS,BYPASS: begin
                    if(abort_frame) state<=IDLE;
                    else if(consume_pixel && !geometry_bad && !fault_event) begin
                        m_valid<=1; m_data<=p2_data; m_sof<=p2_flags[1]; m_eol<=p2_flags[0];
                        frame_word<=frame_word+1'b1;
                        line_word<=p2_flags[0] ? 0:line_word+1'b1;
                        if(use_history) begin
                            motion_count<=motion_count+{31'b0,p2_motion[0]}+{31'b0,p2_motion[1]};
                            filtered_count<=filtered_count+{31'b0,!p2_motion[0]}+{31'b0,!p2_motion[1]};
                        end
                        if(frame_memory) begin
                            result[chunk_word[7:2]][chunk_word[1:0]*32 +:32]<=p2_data;
                            if(chunk_word==255) begin
                                chunk_word<=0; write_beat<=0;
                                m_axi_awvalid<=1; m_axi_wvalid<=1; state<=WRITE_DATA;
                            end else chunk_word<=chunk_word+1'b1;
                        end else begin
                            chunk_word<=chunk_word+1'b1;
                            if(frame_word==FRAME_WORDS-1) begin
                                frame_count<=frame_count+1'b1; frame_done<=1; state<=IDLE;
                            end
                        end
                    end
                end
                WRITE_DATA: begin
                    if(m_axi_awvalid && m_axi_awready) m_axi_awvalid<=0;
                    if(m_axi_wvalid && m_axi_wready) begin
                        if(write_beat==63) m_axi_wvalid<=0;
                        else write_beat<=write_beat+1'b1;
                    end
                    if((!m_axi_awvalid || m_axi_awready) &&
                       (!m_axi_wvalid || (m_axi_wready && write_beat==63))) state<=WRITE_RESP;
                end
                WRITE_RESP: if(m_axi_bvalid) begin
                    if(m_axi_bresp!=0) begin
                        history_valid<=0; m_fault<=1; abort_frame<=1;
                        ddr_error_count<=ddr_error_count+1'b1;
                        fault_count<=fault_count+1'b1; state<=IDLE;
                    end else if(abort_frame || fault_event) state<=IDLE;
                    else if(frame_word==FRAME_WORDS) begin
                        read_bank<=!read_bank; history_valid<=1;
                        frame_count<=frame_count+1'b1; frame_done<=1; state<=IDLE;
                    end else begin
                        chunk_offset<=chunk_offset+1024;
                        if(use_history) state<=READ_ADDR; else state<=PROCESS;
                    end
                end
                default: state<=IDLE;
            endcase
            // Sticky until a new SOF. Never revoke AXI VALID during recovery.
            if(fault_event) begin
                abort_frame<=1; history_valid<=0; m_fault<=1;
                if(!m_fault) fault_count<=fault_count+1'b1;
            end
        end
    end
endmodule
