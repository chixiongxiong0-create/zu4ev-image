`timescale 1ns/1ps
// Directed and randomized verification of the dynamic two-lane DPC. The model
// below is an independent coordinate-based integer implementation of the
// documented algorithm; it never reuses RTL taps or RTL rounding helpers.
module tb_dpc_dynamic;
    parameter integer W = 64;
    parameter integer H = 24;
    localparam integer QD = 4;

    reg clk = 0;
    always #2.5 clk = ~clk;

    reg resetn = 0;
    reg sv = 0, ss = 0, se = 0, sp = 0, sf = 0;
    reg [19:0] sd = 0;
    wire [19:0] md;
    wire mv, ms, me, mp, mf;
    reg cw = 0, cr = 0;
    reg [15:0] wa = 0, ra = 0;
    reg [31:0] wd = 0;
    wire [31:0] rd;
    wire ok;

    dpc_dynamic_raw10 #(.WIDTH(W),.HEIGHT(H)) dut (
        .clk(clk),.resetn(resetn),
        .s_data(sd),.s_valid(sv),.s_sof(ss),.s_eol(se),
        .s_packet_error(sp),.s_global_fault(sf),
        .m_data(md),.m_valid(mv),.m_sof(ms),.m_eol(me),
        .m_packet_error(mp),.m_global_fault(mf),
        .csr_write(cw),.csr_read(cr),.csr_waddr(wa),.csr_raddr(ra),
        .csr_wdata(wd),.csr_write_ok(ok),.csr_rdata(rd));

    reg [9:0] src [0:1][0:H-1][0:W-1];
    reg [9:0] expbuf [0:1][0:H-1][0:W-1];

    integer q_slot [0:QD-1];
    integer q_hot [0:QD-1];
    integer q_cold [0:QD-1];
    integer q_rep [0:QD-1];
    integer q_head = 0, q_tail = 0;

    integer frames_done = 0, frame_seq_exp = 0;
    integer checked = 0, pair_in_frame = 0;
    integer xout = 0, yout = 0;
    integer seed = 32'h1b2c3d4e;
    integer abort_frame = 0;
    integer base_frames = 0;
    integer m_hot = 0, m_cold = 0, m_repair = 0;
    integer exp_apply = 0;
    integer exp_faults = 0;
    integer model_slot = 0, src_slot = 0;

    task automatic drive_pair(input integer slot, input integer x, input integer y);
        begin
            @(negedge clk);
            sv = 1;
            ss = (x == 0 && y == 0);
            se = (x == W-2);
            sd = {src[slot][y][x+1], src[slot][y][x]};
        end
    endtask

    task automatic idle;
        begin
            @(negedge clk);
            sv = 0; ss = 0; se = 0; sd = 0;
        end
    endtask

    function automatic [9:0] src_pixel(input integer fid, input integer x, input integer y);
        integer v;
        begin
            v = (x*37 + y*53 + fid*7 + ((x*y)>>2)) & 1023;
            case (y)
                1,2: v = 300;
                3: v = (x < W/2) ? 120 : 880;
                4,5,6: v = 300;
                7,8,9: v = 300;
                10: v = ((x & 1) == 0) ? 720 : 280;
                11,12,13: v = 0;
                14,15,16: v = 1023;
                17,18,19: v = 400;
                20: v = (x == 10) ? 1023 : (x == 30) ? 0 :
                         ((x*17 + y*29 + fid*5) & 1023);
                default: v = v;
            endcase
            if (y == 5) begin
                if (x == 6) v = 332;   // hot equality: p == hi + margin
                if (x == 10) v = 333;  // hot one beyond
                if (x == 14) v = 268;  // cold equality: p + margin == lo
                if (x == 18) v = 267;  // cold one beyond
            end
            if (y == 8) begin
                if (x == 40) v = 324;  // flatness exactly 24
                if (x == 41) v = 400;
                if (x == 44) v = 325;  // flatness 25: not flat
                if (x == 45) v = 401;
            end
            if (y == 12 && (x == 6 || x == 12 || x == 18)) v = 1023;
            if (y == 15 && (x == 6 || x == 12 || x == 18)) v = 0;
            if (y == 18) begin
                if (x >= 8 && x <= 10) v = 1023;
                if (x >= 20 && x <= 22) v = 0;
            end
            src_pixel = v[9:0];
        end
    endfunction

    task automatic build_frame(input integer fid, input integer slot);
        integer x, y;
        begin
            for (y = 0; y < H; y = y + 1)
                for (x = 0; x < W; x = x + 1)
                    src[slot][y][x] = src_pixel(fid, x, y);
        end
    endtask

    // Independent integer model. Writes expbuf[slot_exp] and leaves the frame
    // counters in m_hot/m_cold/m_repair.
    task automatic model_frame(input integer slot_src, input integer slot_exp,
                               input integer mode, input integer hen, input integer cen,
                               input integer hm, input integer cm, input integer fl);
        integer x, y, lane, cx;
        reg [9:0] p, n0,n1,n2,n3,n4,n5,n6,n7, lo, hi;
        reg [9:0] dh, dv, dd1, dd2, aa, bb;
        reg [10:0] p11, hi11, lo11;
        reg flat, hot, cold;
        begin
            m_hot = 0; m_cold = 0; m_repair = 0;
            for (y = 0; y < H; y = y + 1) begin
                for (x = 0; x < W; x = x + 2) begin
                    for (lane = 0; lane < 2; lane = lane + 1) begin
                        cx = x + lane;
                        p = src[slot_src][y][cx];
                        if (y == 0 || y == H-1 || cx == 0 || cx == W-1) begin
                            expbuf[slot_exp][y][cx] = p;
                        end else begin
                            if (lane == 0) begin
                                n0 = src[slot_src][y-1][x-1];
                                n1 = src[slot_src][y-1][x];
                                n2 = src[slot_src][y-1][x+1];
                                n3 = src[slot_src][y][x-1];
                                n4 = src[slot_src][y][x+1];
                                n5 = src[slot_src][y+1][x-1];
                                n6 = src[slot_src][y+1][x];
                                n7 = src[slot_src][y+1][x+1];
                            end else begin
                                n0 = src[slot_src][y-1][x];
                                n1 = src[slot_src][y-1][x+1];
                                n2 = src[slot_src][y-1][x+2];
                                n3 = src[slot_src][y][x];
                                n4 = src[slot_src][y][x+2];
                                n5 = src[slot_src][y+1][x];
                                n6 = src[slot_src][y+1][x+1];
                                n7 = src[slot_src][y+1][x+2];
                            end
                            lo = n0; hi = n0;
                            if (n1 < lo) lo = n1; if (n1 > hi) hi = n1;
                            if (n2 < lo) lo = n2; if (n2 > hi) hi = n2;
                            if (n3 < lo) lo = n3; if (n3 > hi) hi = n3;
                            if (n4 < lo) lo = n4; if (n4 > hi) hi = n4;
                            if (n5 < lo) lo = n5; if (n5 > hi) hi = n5;
                            if (n6 < lo) lo = n6; if (n6 > hi) hi = n6;
                            if (n7 < lo) lo = n7; if (n7 > hi) hi = n7;
                            flat = ((hi - lo) <= fl);
                            p11  = {1'b0, p};
                            hi11 = {1'b0, hi};
                            lo11 = {1'b0, lo};
                            hot  = flat && (hen != 0) && (p11 > (hi11 + hm));
                            cold = flat && (cen != 0) && ((p11 + cm) < lo11);
                            if ((hot || cold) && mode != 0) begin
                                if (hot)  m_hot  = m_hot + 1;
                                if (cold) m_cold = m_cold + 1;
                                if (mode == 2) m_repair = m_repair + 1;
                            end
                            if (mode == 2 && (hot || cold)) begin
                                dh  = (n3 >= n4)  ? (n3 - n4)  : (n4 - n3);
                                dv  = (n1 >= n6)  ? (n1 - n6)  : (n6 - n1);
                                dd1 = (n0 >= n7)  ? (n0 - n7)  : (n7 - n0);
                                dd2 = (n2 >= n5)  ? (n2 - n5)  : (n5 - n2);
                                if ((dh <= dv) && (dh <= dd1) && (dh <= dd2)) begin
                                    aa = n3; bb = n4;
                                end else if ((dv <= dd1) && (dv <= dd2)) begin
                                    aa = n1; bb = n6;
                                end else if (dd1 <= dd2) begin
                                    aa = n0; bb = n7;
                                end else begin
                                    aa = n2; bb = n5;
                                end
                                expbuf[slot_exp][y][cx] =
                                    ({1'b0,aa} + {1'b0,bb} + 11'd1) >> 1;
                            end else begin
                                expbuf[slot_exp][y][cx] = p;
                            end
                        end
                    end
                end
            end
        end
    endtask

    task automatic push_frame(input integer slot,
                              input integer hot, input integer cold,
                              input integer repair);
        begin
            q_slot[q_tail] = slot;
            q_hot[q_tail] = hot;
            q_cold[q_tail] = cold;
            q_rep[q_tail] = repair;
            q_tail = (q_tail + 1) % QD;
        end
    endtask

    // ------------------------------------------------------------------
    // Output checker. Every emitted pair is compared with the model image of
    // the frame whose configuration was queued before its input started.
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        #1;
        if (resetn && mv) begin
            if (abort_frame && ms) begin
                abort_frame = 0;
                q_head = (q_head + 1) % QD;
                xout = 0;
                yout = 0;
                pair_in_frame = 0;
            end
            if (!abort_frame) begin
                if (ms !== (xout == 0 && yout == 0))
                    $fatal(1,"SOF mismatch frame %0d (%0d,%0d)",frames_done,xout,yout);
                if (expbuf[q_slot[q_head]][yout][xout] !== md[9:0] ||
                    expbuf[q_slot[q_head]][yout][xout+1] !== md[19:10])
                    $fatal(1,"pixel frame%0d (%0d,%0d) got %h want %0d/%0d",
                           frames_done,xout,yout,md,
                           expbuf[q_slot[q_head]][yout][xout],
                           expbuf[q_slot[q_head]][yout][xout+1]);
                checked = checked + 1;
                pair_in_frame = pair_in_frame + 1;
                if (me) begin
                    if (xout != W-2)
                        $fatal(1,"EOL position frame%0d x=%0d",frames_done,xout);
                    xout = 0;
                    if (yout == H-1) begin
                        if (pair_in_frame != W*H/2)
                            $fatal(1,"frame pair count frame%0d %0d",
                                   frames_done,pair_in_frame);
                        pair_in_frame = 0;
                        yout = 0;
                        frames_done = frames_done + 1;
                        frame_seq_exp = frame_seq_exp + 1;
                        q_head = (q_head + 1) % QD;
                    end else yout = yout + 1;
                end else begin
                    if (xout >= W-2)
                        $fatal(1,"extra pair frame%0d x=%0d",frames_done,xout);
                    xout = xout + 2;
                end
            end
        end
    end

    always @(negedge resetn) begin
        frame_seq_exp = 0;
    end

    task automatic write_csr(input [15:0] a, input [31:0] v, input bit accepted);
        begin
            @(negedge clk); wa = a; wd = v; cw = 1;
            #1;
            if (ok !== accepted)
                $fatal(1,"write %h value %h expected acceptance %d",a,v,accepted);
            @(negedge clk); cw = 0;
        end
    endtask

    task automatic read_check(input [15:0] a, input [31:0] v);
        begin
            @(negedge clk); ra = a; cr = 1;
            @(posedge clk); #2;
            if (rd !== v) $fatal(1,"read %h got %h want %h",a,rd,v);
            @(negedge clk); cr = 0;
        end
    endtask

    task automatic read_check_masked(input [15:0] a, input [31:0] mask, input [31:0] v);
        begin
            @(negedge clk); ra = a; cr = 1;
            @(posedge clk); #2;
            if ((rd & mask) !== (v & mask))
                $fatal(1,"read %h got %h want %h mask %h",a,rd,v,mask);
            @(negedge clk); cr = 0;
        end
    endtask

    // Bounded wait on the monotonic completed-frame counter. The limit is
    // derived from the geometry: one pair beat per clock, with a factor of two
    // and a fixed allowance covering CSR traffic, bubbles and pipeline drain.
    // This turns a lost output frame into an immediate fatal instead of a
    // silent run into the global watchdog.
    task automatic wait_frames(input integer target, input string what);
        integer limit_ns, goal;
        begin
            goal = target;
            limit_ns = (W*H/2)*10 + 50000;
            fork
                wait (frames_done >= goal);
                begin
                    #(limit_ns);
                    $fatal(1,"%s timeout target=%0d frames=%0d",what,goal,frames_done);
                end
            join_any
            disable fork;
        end
    endtask

    task automatic set_config(input integer mode, input integer hen, input integer cen,
                              input integer hm, input integer cm, input integer fl);
        begin
            write_csr(16'h3164, {28'd0,cen[0],hen[0],mode[1:0]}, 1);
            write_csr(16'h3168, {2'd0,fl[9:0],cm[9:0],hm[9:0]}, 1);
            write_csr(16'h316c, 32'd1, 1);
            read_check(16'h3164, {28'd0,cen[0],hen[0],mode[1:0]});
            read_check(16'h3168, {2'd0,fl[9:0],cm[9:0],hm[9:0]});
            read_check_masked(16'h3170, 32'h100, 32'h100);
        end
    endtask

    task automatic send_frame(input integer slot, input integer bubbles);
        integer x, y;
        begin
            for (y = 0; y < H; y = y + 1)
                for (x = 0; x < W; x = x + 2) begin
                    if (bubbles != 0 && ((($random(seed)) & 7) == 0)) idle();
                    drive_pair(slot, x, y);
                end
            idle();
        end
    endtask

    task automatic run_frame(input integer fid, input integer mode,
                             input integer hen, input integer cen,
                             input integer hm, input integer cm, input integer fl,
                             input integer bubbles, input integer commit);
        integer send_slot, exp_slot, expect_frames;
        begin
            if (commit != 0) begin
                set_config(mode,hen,cen,hm,cm,fl);
                exp_apply = exp_apply + 1;
            end
            send_slot = src_slot;
            exp_slot = model_slot;
            build_frame(fid, send_slot);
            model_frame(send_slot, exp_slot, mode,hen,cen,hm,cm,fl);
            push_frame(exp_slot, m_hot, m_cold, m_repair);
            src_slot = (src_slot + 1) % 2;
            model_slot = (model_slot + 1) % 2;
            expect_frames = frames_done + 1;
            send_frame(send_slot, bubbles);
            wait_frames(expect_frames, "frame output");
            repeat(2) @(negedge clk);
            // The commit is visible in the active registers only after the
            // frame start that consumed it.
            if (commit != 0) begin
                read_check(16'h3170, {23'd0,1'b0,4'd0,cen[0],hen[0],mode[1:0]});
                read_check(16'h3174, {2'd0,fl[9:0],cm[9:0],hm[9:0]});
            end
            read_check(16'h317c, frame_seq_exp);
            read_check(16'h3178, exp_apply);
            read_check(16'h3180, q_hot[(q_head + QD - 1) % QD]);
            read_check(16'h3184, q_cold[(q_head + QD - 1) % QD]);
            read_check(16'h3188, q_rep[(q_head + QD - 1) % QD]);
            read_check(16'h318c, exp_faults);
        end
    endtask

    initial begin
        if (W < 64 || H < 24) $fatal(1,"geometry must be at least 64x24");
        repeat(5) @(negedge clk);
        resetn = 1;
        read_check(16'h3160, 32'h44504344);
        read_check(16'h3164, 32'h0000000c);
        read_check(16'h3168, 32'h01808020);
        read_check(16'h3170, 32'h0000000c);
        read_check(16'h3174, 32'h01808020);
        read_check(16'h3178, 0);
        read_check(16'h317c, 0);
        read_check(16'h3180, 0);
        read_check(16'h3184, 0);
        read_check(16'h3188, 0);
        read_check(16'h318c, 0);
        read_check(16'h316c, 0);

        // Rejected shadow programming: reserved bits, invalid mode, wrong
        // commit value, and writes to read-only active registers.
        write_csr(16'h3164, 32'h10, 0);
        write_csr(16'h3164, 32'h3, 0);
        write_csr(16'h3168, 32'h40000000, 0);
        write_csr(16'h316c, 32'h2, 0);
        write_csr(16'h316c, 32'h0, 0);
        write_csr(16'h3170, 32'h1, 0);

        // Default bypass frame with input bubbles.
        run_frame(0, 0,1,1,32,32,24, 1, 0);
        // Observe: candidates counted, pixels untouched.
        run_frame(1, 1,1,1,32,32,24, 0, 1);
        // Repair: candidate pixels replaced by the smoothest symmetric mean.
        run_frame(2, 2,1,1,32,32,24, 0, 1);
        // Cold-only repair with margins 0 and flatness 0.
        run_frame(3, 2,1,0,0,0,0, 1, 1);
        // Margins 1023: no candidate at all, bit-exact passthrough.
        run_frame(4, 2,1,1,1023,1023,24, 0, 1);
        // Full flatness limit, hot-only detection.
        run_frame(5, 2,1,0,32,32,1023, 1, 1);

        // A queued commit rejects further shadow and commit writes.
        write_csr(16'h3164, 32'h0000000c, 1);
        write_csr(16'h316c, 32'h1, 1);
        write_csr(16'h3164, 32'h0000000d, 0);
        write_csr(16'h3168, 32'h00000000, 0);
        write_csr(16'h316c, 32'h1, 0);
        read_check(16'h3170, 32'h00000106);
        // Bypass stays pending across a held stream fault and a malformed EOL.
        build_frame(6, src_slot);
        for (integer n = 0; n < 4; n = n + 1) drive_pair(src_slot, n*2, 0);
        repeat(3) begin
            @(negedge clk); sv = 1; ss = 0; se = 0; sp = 1; sd = 0;
        end
        @(negedge clk); sp = 0; idle();
        exp_faults = exp_faults + 1;
        read_check(16'h318c, exp_faults);
        read_check(16'h3170, 32'h00000106);
        build_frame(7, src_slot);
        for (integer n = 0; n < 4; n = n + 1) begin
            @(negedge clk); sv = 1; ss = (n == 0); se = (n == 2); sd = src[src_slot][0][n*2];
        end
        idle();
        exp_faults = exp_faults + 1;
        read_check(16'h318c, exp_faults);
        // Clean frame applies the retained pending bypass commit.
        exp_apply = exp_apply + 1;
        run_frame(8, 0,1,1,32,32,24, 0, 0);
        read_check(16'h3170, 32'h0000000c);
        // The rejected threshold write left the shadow threshold from frame 5,
        // so the retained snapshot applies flat limit 1023 with bypass mode.
        read_check(16'h3174, 32'h3ff08020);

        // Two adjacent frames with two different pending configurations. The
        // second commit lands in the middle of the first frame's input, after
        // that frame has been latched but before the second frame starts.
        set_config(2,1,1,32,32,24); exp_apply = exp_apply + 1;
        build_frame(9, 0);
        model_frame(0, 0, 2,1,1,32,32,24);
        push_frame(0, m_hot, m_cold, m_repair);
        build_frame(10, 1);
        model_frame(1, 1, 0,1,1,32,32,24);
        push_frame(1, m_hot, m_cold, m_repair);
        src_slot = 0; model_slot = 0;
        // Relative frame targets: earlier directed frames may complete any
        // number of frames before this block, so absolute equality waits would
        // either fire early or deadlock.
        base_frames = frames_done;
        fork
            begin
                for (integer y = 0; y < H; y = y + 1)
                    for (integer x = 0; x < W; x = x + 2) begin
                        drive_pair(0, x, y);
                        if (x == 0 && y == H/2) begin
                            // CSR activity inserts idle beats; without them the
                            // last pair would be held for an extra cycle and
                            // corrupt the row geometry.
                            idle();
                            set_config(0,1,1,32,32,24);
                            exp_apply = exp_apply + 1;
                        end
                    end
                for (integer y = 0; y < H; y = y + 1)
                    for (integer x = 0; x < W; x = x + 2)
                        drive_pair(1, x, y);
                idle();
            end
            begin
                wait_frames(base_frames + 1, "adjacent first frame");
                repeat(2) @(negedge clk);
                read_check(16'h3180, q_hot[(q_head + QD - 1) % QD]);
                read_check(16'h3188, q_rep[(q_head + QD - 1) % QD]);
                wait_frames(base_frames + 2, "adjacent second frame");
            end
        join
        repeat(2) @(negedge clk);
        read_check(16'h317c, frame_seq_exp);
        read_check(16'h3178, exp_apply);
        read_check(16'h3180, q_hot[(q_head + QD - 1) % QD]);
        read_check(16'h3188, q_rep[(q_head + QD - 1) % QD]);
        read_check(16'h3170, 32'h0000000c);
        read_check(16'h3174, 32'h01808020);

        // Fault while earlier data is still in flight: abort the current
        // output frame and resynchronise on the next clean SOF.
        build_frame(11, 0);
        model_frame(0, 0, 0,1,1,32,32,24);
        push_frame(0, m_hot, m_cold, m_repair);
        for (integer n = 0; n < (W/2)*3; n = n + 1)
            drive_pair(0, (n % (W/2))*2, n/(W/2));
        abort_frame = 1;
        for (integer n = 0; n < 2; n = n + 1) begin
            @(negedge clk); sv = 1; ss = 0; se = 0; sp = 1; sd = 0;
        end
        @(negedge clk); sp = 0; idle();
        exp_faults = exp_faults + 1;
        repeat(4) @(negedge clk);
        set_config(1,1,1,32,32,24); exp_apply = exp_apply + 1;
        run_frame(12, 1,1,1,32,32,24, 0, 0);
        read_check(16'h318c, exp_faults);
        read_check(16'h3170, 32'h0000000d);

        // Reset clears pending, counters and the model expectation.
        @(negedge clk); resetn = 0;
        repeat(3) @(negedge clk);
        resetn = 1;
        q_head = 0; q_tail = 0; abort_frame = 0;
        xout = 0; yout = 0; pair_in_frame = 0;
        exp_apply = 0; exp_faults = 0;
        read_check(16'h3178, 0);
        read_check(16'h317c, 0);
        read_check(16'h318c, 0);
        run_frame(13, 0,1,1,32,32,24, 1, 0);

        if (checked < frames_done * (W*H/2))
            $fatal(1,"checked %0d frames %0d",checked,frames_done);
        $display("DPC_DYNAMIC_PASS %0dx%0d frames=%0d pairs=%0d faults=%0d seed=1b2c3d4e",
                 W,H,frames_done,checked,exp_faults);
        $finish;
    end


    initial begin #2000000000; $fatal(1,"timeout"); end
endmodule
