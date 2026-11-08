`timescale 1ns/1ps
// Two-pixel Mono DPC: only a confirmed coordinate map can change pixels.
module dpc_raw10 #(
    parameter integer WIDTH=1280, HEIGHT=1024, MAX_RUNS=1024, PROBE_LIMIT=1024
)(
    input wire clk, resetn,
    input wire [19:0] s_data, cal_data,
    input wire s_valid, s_sof, s_eol, s_packet_error, s_global_fault,
    input wire cal_valid, cal_sof, cal_eol, cal_fault,
    output reg [19:0] m_data,
    output reg m_valid, m_sof, m_eol, m_packet_error, m_global_fault,
    input wire csr_write, csr_read,
    input wire [15:0] csr_waddr, csr_raddr,
    input wire [31:0] csr_wdata,
    output wire csr_write_ok,
    output wire [31:0] csr_rdata
);
    localparam integer MAP_AB = $clog2(MAX_RUNS);
    localparam integer LOOKAHEAD = 16;

    reg [MAP_AB:0] declared_count, uploaded, active_count, pending_count, run_index;
    reg declared_valid, active_bank, active_enable, pending, pending_enable;
    reg [31:0] apply_seq;
    reg [25:0] first_run [0:1];
    reg [9:0] previous_y;
    reg [11:0] previous_end;
    (* ram_style="distributed" *) reg [25:0] map_mem [0:2*MAX_RUNS-1];

    wire map_write = csr_waddr >= 16'h8000 && csr_waddr < 16'h8000+4*MAX_RUNS;
    wire map_read = csr_raddr >= 16'h8000 && csr_raddr < 16'h8000+4*MAX_RUNS;
    wire [MAP_AB-1:0] write_index = csr_waddr[MAP_AB+1:2];
    wire [MAP_AB-1:0] read_index = csr_raddr[MAP_AB+1:2];
    wire [10:0] entry_x = csr_wdata[10:0];
    wire [9:0] entry_y = csr_wdata[20:11];
    wire [5:0] entry_len = {1'b0,csr_wdata[25:21]} + 6'd1;
    wire [11:0] entry_end = {1'b0,entry_x} + {6'd0,entry_len};
    wire ordered = uploaded == 0 || entry_y > previous_y ||
                   (entry_y == previous_y && {1'b0,entry_x} > previous_end);
    wire entry_ok = csr_wdata[31:26] == 0 && entry_y < HEIGHT &&
                    entry_end <= WIDTH && entry_len < WIDTH && ordered;

    reg [11:0] probe_cfg_hi;
    reg [9:0] probe_threshold;
    wire probe_low = probe_cfg_hi[6];
    wire probe_corrected = probe_cfg_hi[7];
    wire probe_busy, probe_done, probe_overflow, probe_failed;
    wire [10:0] probe_count0, probe_count1;
    wire [31:0] probe_seq, probe_rdata;
    wire probe_read = csr_read && csr_raddr >= 16'ha000 && csr_raddr < 16'hc000;
    wire probe_start = csr_write && csr_write_ok && csr_waddr == 16'h3144;

    assign csr_write_ok = csr_waddr[1:0] == 0 && (
        (csr_waddr == 16'h3108 && !pending &&
          (csr_wdata == 2 || (csr_wdata == 3 && declared_valid && uploaded == declared_count))) ||
        (csr_waddr == 16'h3110 && !pending && csr_wdata <= MAX_RUNS) ||
        (map_write && !pending && declared_valid && uploaded < declared_count &&
          {1'b0,write_index} == uploaded && entry_ok) ||
        (csr_waddr == 16'h3140 && !probe_busy && (csr_wdata & 32'hfffcfc00) == 0) ||
        (csr_waddr == 16'h3144 && !probe_busy && csr_wdata == 1));

    dpc_probe #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.CAPTURE_LIMIT(PROBE_LIMIT)) probe (
        .clk(clk),.resetn(resetn),.start(probe_start),.low(probe_low),
        .threshold(probe_threshold),.data(probe_corrected ? m_data : cal_data),
        .valid(probe_corrected ? m_valid : cal_valid),
        .sof(probe_corrected ? m_sof : cal_sof),.eol(probe_corrected ? m_eol : cal_eol),
        .fault(probe_corrected ? (m_packet_error || m_global_fault) : cal_fault),
        .read_enable(probe_read),.read_lane(csr_raddr[12]),.read_index(csr_raddr[11:2]),
        .read_data(probe_rdata),.busy(probe_busy),.done(probe_done),.overflow(probe_overflow),
        .failed(probe_failed),.count0(probe_count0),.count1(probe_count1),.capture_seq(probe_seq));

    // Position on input is independently checked before pixels enter the FIFO.
    reg input_open;
    reg [10:0] in_x;
    reg [9:0] in_y;
    wire [10:0] push_x = s_sof ? 11'd0 : in_x;
    wire [9:0] push_y = s_sof ? 10'd0 : in_y;
    wire input_candidate = s_valid && (input_open || s_sof);
    wire geometry_fault = input_candidate &&
                          ((input_open && s_sof) || (s_eol != (push_x == WIDTH-2)));

    (* ram_style="distributed" *) reg [21:0] fifo [0:31];
    reg [4:0] wr_ptr, rd_ptr;
    reg [5:0] occupancy, complete_rows;
    wire pop_possible = occupancy > LOOKAHEAD || complete_rows != 0;
    wire stream_fault = s_packet_error || s_global_fault || geometry_fault ||
                        (input_candidate && occupancy == 32 && !pop_possible);
    wire push = input_candidate && !stream_fault;
    wire pop = pop_possible && !stream_fault;
    wire [21:0] head = fifo[rd_ptr];
    wire head_sof = head[21];
    wire head_eol = head[20];
    wire [19:0] head_data = head[19:0];

    always @(posedge clk) begin
        if (push) begin
            fifo[wr_ptr] <= {s_sof,s_eol,s_data};
        end
        if (!resetn || stream_fault) begin
            input_open <= 1'b0;
            in_x <= 11'd0;
            in_y <= 10'd0;
            wr_ptr <= 5'd0;
            rd_ptr <= 5'd0;
            occupancy <= 6'd0;
            complete_rows <= 6'd0;
        end else begin
            if (push) begin
                input_open <= !(s_eol && push_y == HEIGHT-1);
                in_x <= s_eol ? 11'd0 : push_x + 11'd2;
                in_y <= s_eol ? push_y + 1'b1 : push_y;
                wr_ptr <= wr_ptr + 1'b1;
            end
            if (pop) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
            case ({push,pop})
                2'b10: occupancy <= occupancy + 1'b1;
                2'b01: occupancy <= occupancy - 1'b1;
                default: begin end
            endcase
            case ({push && s_eol,pop && head_eol})
                2'b10: complete_rows <= complete_rows + 1'b1;
                2'b01: complete_rows <= complete_rows - 1'b1;
                default: begin end
            endcase
        end
    end

    wire commit = pop && head_sof && pending;
    wire video_bank = active_bank ^ (commit && pending_enable);
    wire video_enable = commit ? pending_enable : active_enable;
    wire [MAP_AB:0] video_count = commit && pending_enable ? pending_count : active_count;
    wire [MAP_AB:0] lookup = head_sof ? 0 : run_index;
    reg [25:0] current_run;
    wire [MAP_AB-1:0] next_index = lookup[MAP_AB-1:0] + 1'b1;
    wire [25:0] next_run = map_mem[{video_bank,next_index}];
    wire [25:0] run = head_sof ? first_run[video_bank] : current_run;

    always @(posedge clk) begin
        if (resetn && csr_write && csr_write_ok && map_write) begin
            map_mem[{!active_bank,write_index}] <= csr_wdata[25:0];
            if (write_index == 0) begin first_run[!active_bank] <= csr_wdata[25:0]; end
        end
        if (!resetn) begin
            declared_count <= 0;
            uploaded <= 0;
            declared_valid <= 0;
            active_count <= 0;
            active_bank <= 0;
            active_enable <= 0;
            pending <= 0;
            pending_enable <= 0;
            pending_count <= 0;
            previous_y <= 0;
            previous_end <= 0;
            apply_seq <= 0;
            probe_cfg_hi <= 0;
            probe_threshold <= 10'd128;
        end else begin
            if (csr_write && csr_write_ok) begin
                case (csr_waddr)
                    16'h3108: begin
                        pending <= 1'b1;
                        pending_enable <= csr_wdata[0];
                        pending_count <= declared_count;
                    end
                    16'h3110: begin
                        declared_valid <= 1'b1;
                        declared_count <= csr_wdata[MAP_AB:0];
                        uploaded <= 0;
                    end
                    16'h3140: begin
                        probe_cfg_hi <= csr_wdata[21:10];
                        probe_threshold <= csr_wdata[9:0];
                    end
                    default: if (map_write) begin
                        uploaded <= uploaded + 1'b1;
                        previous_y <= entry_y;
                        previous_end <= entry_end;
                    end
                endcase
            end
            if (commit) begin
                active_enable <= pending_enable;
                if (pending_enable) begin
                    active_bank <= !active_bank;
                    active_count <= pending_count;
                end
                declared_valid <= 1'b0;
                uploaded <= 0;
                pending <= 1'b0;
                apply_seq <= apply_seq + 1'b1;
            end
        end
    end

    // The next run cannot start in the other lane of the same pair: same-row
    // runs must have a good pixel between them.
    reg [10:0] out_x;
    reg [9:0] out_y;
    reg [9:0] last_good, saved_left;
    wire [10:0] px = head_sof ? 11'd0 : out_x;
    wire [9:0] py = head_sof ? 10'd0 : out_y;
    wire [10:0] px1 = {px[10:1],1'b1};
    wire [10:0] run_x = run[10:0];
    wire [9:0] run_y = run[20:11];
    wire [5:0] run_len = {1'b0,run[25:21]} + 6'd1;
    wire [11:0] run_end = {1'b0,run_x} + {6'd0,run_len};
    wire run_on_row = video_enable && lookup < video_count && run_y == py;
    wire hit0 = run_on_row && px >= run_x && {1'b0,px} < run_end;
    wire hit1 = run_on_row && px1 >= run_x && {1'b0,px1} < run_end;
    wire start_run = (hit0 || hit1) && (run_x == px || run_x == px1);
    wire end_run = (hit0 || hit1) && {1'b0,px1} + 12'd1 >= run_end;
    wire [9:0] left = start_run ? (run_x[0] ? head_data[9:0] : last_good) : saved_left;
    wire [5:0] right_delta = 6'(run_end - {1'b0,px});
    wire [4:0] right_ptr = rd_ptr + right_delta[5:1];
    wire have_left = run_x != 0;
    wire have_right = run_end < WIDTH;
    wire [5:0] offset0 = 6'(px - run_x);
    wire [5:0] offset1 = offset0 + 6'd1;

    function automatic [23:0] reciprocal(input [5:0] divisor);
        case (divisor)
            6'd2: reciprocal = 24'd8388608;
            6'd3: reciprocal = 24'd5592406;
            6'd4: reciprocal = 24'd4194304;
            6'd5: reciprocal = 24'd3355444;
            6'd6: reciprocal = 24'd2796203;
            6'd7: reciprocal = 24'd2396746;
            6'd8: reciprocal = 24'd2097152;
            6'd9: reciprocal = 24'd1864136;
            6'd10: reciprocal = 24'd1677722;
            6'd11: reciprocal = 24'd1525202;
            6'd12: reciprocal = 24'd1398102;
            6'd13: reciprocal = 24'd1290556;
            6'd14: reciprocal = 24'd1198373;
            6'd15: reciprocal = 24'd1118482;
            6'd16: reciprocal = 24'd1048576;
            6'd17: reciprocal = 24'd986896;
            6'd18: reciprocal = 24'd932068;
            6'd19: reciprocal = 24'd883012;
            6'd20: reciprocal = 24'd838861;
            6'd21: reciprocal = 24'd798916;
            6'd22: reciprocal = 24'd762601;
            6'd23: reciprocal = 24'd729445;
            6'd24: reciprocal = 24'd699051;
            6'd25: reciprocal = 24'd671089;
            6'd26: reciprocal = 24'd645278;
            6'd27: reciprocal = 24'd621379;
            6'd28: reciprocal = 24'd599187;
            6'd29: reciprocal = 24'd578525;
            6'd30: reciprocal = 24'd559241;
            6'd31: reciprocal = 24'd541201;
            6'd32: reciprocal = 24'd524288;
            6'd33: reciprocal = 24'd508401;
            default: reciprocal = 24'd0;
        endcase
    endfunction

    function automatic [15:0] numerator(
        input [9:0] l,r, input [5:0] length, offset
    );
        reg [5:0] lw,rw,divisor;
        begin
            lw = length - offset;
            rw = offset + 6'd1;
            divisor = length + 6'd1;
            numerator = l*lw + r*rw + {11'd0,divisor[5:1]};
        end
    endfunction

    always @(posedge clk) begin
        if (!resetn || stream_fault) begin
            out_x <= 0;
            out_y <= 0;
            run_index <= 0;
            last_good <= 0;
            saved_left <= 0;
        end else if (pop) begin
            out_x <= head_eol ? 11'd0 : px + 11'd2;
            out_y <= head_eol ? py + 1'b1 : py;
            run_index <= end_run ? lookup + 1'b1 : lookup;
            if (end_run) begin
                current_run <= next_run;
            end else if (head_sof) begin
                current_run <= run;
            end
            if (!hit1) begin
                last_good <= head_data[19:10];
            end else if (!hit0) begin
                last_good <= head_data[9:0];
            end
            if (start_run) begin
                saved_left <= left;
            end
        end
    end

    // Register the tap address before the donor read and weighted sums. The
    // FIFO never holds over 17 pairs; a popped entry cannot be overwritten
    // on the very next clock in this 32-entry store.
    reg valid_a, sof_a, eol_a, eof_a;
    reg [1:0] hits_a;
    reg [19:0] raw_a;
    reg [4:0] right_ptr_a;
    reg right_lane_a, have_left_a, have_right_a;
    reg [9:0] left_a;
    reg [5:0] len_a, off0_a, off1_a;
    wire [19:0] right_pair_a = fifo[right_ptr_a][19:0];
    wire [9:0] right_a = right_lane_a ? right_pair_a[19:10] : right_pair_a[9:0];
    wire [9:0] one_side_a = have_left_a ? left_a : right_a;
    wire [5:0] denom_a = len_a + 6'd1;

    reg valid0, valid1, sof0, sof1, eol0, eol1, eof0, eof1;
    reg [1:0] hits0, hits1, blend0, blend1;
    reg [19:0] raw0, raw1;
    reg [15:0] num0, num1;
    reg [23:0] recip0;
    reg [39:0] product0, product1;
    reg [31:0] frame_seq, last_repaired, repairing, fault_events;
    wire [31:0] add_hits = {31'd0,hits1[0]} + {31'd0,hits1[1]};
    wire [31:0] repaired_next = (sof1 ? 32'd0 : repairing) + add_hits;

    always @(posedge clk) begin
        if (!resetn || stream_fault) begin
            valid_a <= 0;
            valid0 <= 0;
            valid1 <= 0;
            m_valid <= 0;
            m_sof <= 0;
            m_eol <= 0;
        end else begin
            valid_a <= pop;
            valid0 <= valid_a;
            valid1 <= valid0;
            m_valid <= valid1;
            m_sof <= valid1 && sof1;
            m_eol <= valid1 && eol1;
        end
        m_packet_error <= resetn && s_packet_error;
        m_global_fault <= resetn && stream_fault;
        if (pop) begin
            sof_a <= head_sof;
            eol_a <= head_eol;
            eof_a <= head_eol && py == HEIGHT-1;
            hits_a <= {hit1,hit0};
            raw_a <= head_data;
            right_ptr_a <= right_ptr;
            right_lane_a <= right_delta[0];
            have_left_a <= have_left;
            have_right_a <= have_right;
            left_a <= left;
            len_a <= run_len;
            off0_a <= offset0;
            off1_a <= offset1;
        end
        if (valid_a) begin
            sof0 <= sof_a;
            eol0 <= eol_a;
            eof0 <= eof_a;
            hits0 <= hits_a;
            blend0 <= hits_a & {2{have_left_a && have_right_a}};
            raw0 <= {hits_a[1] ? one_side_a : raw_a[19:10],hits_a[0] ? one_side_a : raw_a[9:0]};
            num0 <= numerator(left_a,right_a,len_a,off0_a);
            num1 <= numerator(left_a,right_a,len_a,off1_a);
            recip0 <= reciprocal(denom_a);
        end
        if (valid0) begin
            sof1 <= sof0;
            eol1 <= eol0;
            eof1 <= eof0;
            hits1 <= hits0;
            blend1 <= blend0;
            raw1 <= raw0;
            product0 <= num0 * recip0;
            product1 <= num1 * recip0;
        end
        if (valid1) begin
            m_data <= {blend1[1] ? product1[33:24] : raw1[19:10],
                       blend1[0] ? product0[33:24] : raw1[9:0]};
        end
        if (!resetn) begin
            frame_seq <= 0;
            last_repaired <= 0;
            repairing <= 0;
            fault_events <= 0;
        end else if (stream_fault) begin
            repairing <= 0;
            if (fault_events != 32'hffffffff) begin fault_events <= fault_events + 1'b1; end
        end else if (valid1) begin
            repairing <= repaired_next;
            if (eof1) begin
                frame_seq <= frame_seq + 1'b1;
                last_repaired <= repaired_next;
            end
        end
    end

    reg probe_read_d;
    reg [31:0] regular_rdata;
    assign csr_rdata = probe_read_d ? probe_rdata : regular_rdata;
    always @(posedge clk) begin
        if (!resetn) begin
            probe_read_d <= 1'b0;
            regular_rdata <= 0;
        end else if (csr_read) begin
            probe_read_d <= probe_read;
            if (map_read) begin
                regular_rdata <= {1'b0,read_index} < uploaded ?
                                 {6'd0,map_mem[{!active_bank,read_index}]} : 32'd0;
            end else begin
                case (csr_raddr)
                    16'h3100: regular_rdata <= 32'h44504331;
                    16'h3104: regular_rdata <= 32'h00010000;
                    16'h310c: regular_rdata <= {29'd0,active_bank,pending,active_enable};
                    16'h3114: regular_rdata <= apply_seq;
                    16'h3118: regular_rdata <= 32'(uploaded);
                    16'h311c: regular_rdata <= 32'(active_count);
                    16'h3120: regular_rdata <= frame_seq;
                    16'h3124: regular_rdata <= last_repaired;
                    16'h3128: regular_rdata <= fault_events;
                    16'h312c: regular_rdata <= (HEIGHT<<16)|WIDTH;
                    16'h3130: regular_rdata <= MAX_RUNS;
                    16'h3134: regular_rdata <= 32;
                    16'h3140: regular_rdata <= {10'd0,probe_cfg_hi,probe_threshold};
                    16'h3148: regular_rdata <= {28'd0,probe_failed,probe_overflow,probe_done,probe_busy};
                    16'h314c: regular_rdata <= {21'd0,probe_count0};
                    16'h3150: regular_rdata <= {21'd0,probe_count1};
                    16'h3154: regular_rdata <= probe_seq;
                    default: regular_rdata <= 32'd0;
                endcase
            end
        end
    end
endmodule
