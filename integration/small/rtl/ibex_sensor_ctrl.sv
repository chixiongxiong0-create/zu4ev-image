// SPDX-License-Identifier: Apache-2.0
// Lite-clock CSR, ownership interlock and timer. I2C survives CPU-only reset.
module ibex_sensor_ctrl #(
    parameter int unsigned IdleCycles = 500,
    parameter int unsigned TimeoutCycles = 1000000,
    parameter int unsigned MinHalfPeriod = 125
)(
    input wire clk_i, rst_ni, cpu_rst_ni,
    input wire owner_async_i, run_async_i, stop_async_i,
    input wire ps_scl_release_i, ps_sda_release_i, scl_i, sda_i,
    input wire req_i, we_i,
    input wire [31:0] addr_i, wdata_i,
    input wire [3:0] be_i,
    output wire gnt_o,
    output logic rvalid_o, err_o,
    output logic [31:0] rdata_o,
    output wire scl_low_o, sda_low_o,
    output logic grant_o,
    output wire [31:0] status_o
);
    localparam logic [15:0] MinHalf = 16'(MinHalfPeriod);
    (* ASYNC_REG = "TRUE" *) logic [1:0] owner_sync_q, run_sync_q, stop_sync_q;
    (* ASYNC_REG = "TRUE" *) logic [1:0] scl_sync_q, sda_sync_q;
    (* ASYNC_REG = "TRUE" *) logic [1:0] ps_scl_sync_q, ps_sda_sync_q;
    logic [31:0] ticks_q, idle_cycles_q;
    logic [15:0] half_period_q, register_q;
    logic [7:0] tx_q, rx_q;
    logic [6:0] device_q;
    logic read_q, start_q, done_q, nack_q, timeout_q, rejected_q;
    logic armed_q, restart_q, boot_ready_q, fw_quiescent_q, fault_q;
    logic seen_run_low_q, stop_ack_q;
    (* KEEP = "TRUE" *) logic quiescent_q;
    wire busy, done, nack, timed_out, engine_scl_low, engine_sda_low;
    wire [7:0] rx;
    wire owner = owner_sync_q[1];
    wire run = run_sync_q[1];
    wire lines_idle = scl_sync_q[1] && sda_sync_q[1] &&
        ps_scl_sync_q[1] && ps_sda_sync_q[1];
    wire mux_switch_safe = idle_cycles_q >= IdleCycles && !busy && !start_q;
    wire access = req_i && gnt_o;
    wire aligned_access = addr_i[1:0] == 0;
    wire full_write = access && we_i && aligned_access && be_i == 4'hf;
    wire command_allowed = armed_q && owner && grant_o && cpu_rst_ni && !busy && !start_q;
    wire command_write = full_write && addr_i[7:0] == 8'h10;
    wire command_accept = command_write && wdata_i[0] && command_allowed &&
        (wdata_i & 32'hffff80fc) == 0;
    wire firmware_write = full_write && addr_i[7:0] == 8'h1c;
    wire firmware_ready = firmware_write && wdata_i == 1;
    wire firmware_active = firmware_write && wdata_i == 2 && armed_q;
    wire firmware_quiesce = firmware_write && wdata_i == 4 && !run && !busy && !start_q;
    wire firmware_fault = firmware_write && wdata_i == 8;
    wire arm_event = run && seen_run_low_q && boot_ready_q && grant_o && owner &&
        !armed_q && !fault_q;
    assign gnt_o = req_i && !rvalid_o;
    assign scl_low_o = grant_o && engine_scl_low;
    assign sda_low_o = grant_o && engine_sda_low;
    assign status_o = {22'b0, stop_ack_q, sda_sync_q[1], scl_sync_q[1],
        boot_ready_q, restart_q, fault_q, armed_q, busy, grant_o, quiescent_q};

    ibex_sensor_i2c #(.TimeoutCycles(TimeoutCycles), .MinHalfPeriod(MinHalfPeriod)) u_i2c (
        .clk_i, .rst_ni, .start_i(start_q), .read_i(read_q), .device_i(device_q),
        .register_i(register_q), .half_period_i(half_period_q), .wdata_i(tx_q),
        .scl_i, .sda_i, .scl_low_o(engine_scl_low), .sda_low_o(engine_sda_low),
        .busy_o(busy), .done_o(done), .nack_o(nack), .timeout_o(timed_out), .rdata_o(rx)
    );
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            owner_sync_q <= 0;
            run_sync_q <= 0;
            stop_sync_q <= 0;
            scl_sync_q <= 3;
            sda_sync_q <= 3;
            ps_scl_sync_q <= 3;
            ps_sda_sync_q <= 3;
        end else begin
            owner_sync_q <= {owner_sync_q[0], owner_async_i};
            run_sync_q <= {run_sync_q[0], run_async_i};
            stop_sync_q <= {stop_sync_q[0], stop_async_i};
            scl_sync_q <= {scl_sync_q[0], scl_i};
            sda_sync_q <= {sda_sync_q[0], sda_i};
            ps_scl_sync_q <= {ps_scl_sync_q[0], ps_scl_release_i};
            ps_sda_sync_q <= {ps_sda_sync_q[0], ps_sda_release_i};
        end
    end

    // Mux ownership changes only while both clients release an idle bus.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            ticks_q <= 0;
            idle_cycles_q <= 0;
            grant_o <= 0;
        end else begin
            ticks_q <= ticks_q + 32'd1;
            if (!lines_idle || busy || start_q) begin idle_cycles_q <= 0; end
            else if (idle_cycles_q < IdleCycles) begin idle_cycles_q <= idle_cycles_q + 32'd1; end
            if (grant_o != owner && mux_switch_safe) begin grant_o <= owner; end
        end
    end

    // Firmware lifecycle and stop acknowledgement form a session handshake.
    // RUN0 permits an active byte group to finish; only FW quiescence or CPU
    // reset disarms. Reset never affects the independent transaction engine.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            armed_q <= 0;
            restart_q <= 1;
            boot_ready_q <= 0;
            fw_quiescent_q <= 1;
            fault_q <= 0;
            seen_run_low_q <= 0;
            stop_ack_q <= 0;
            quiescent_q <= 1;
        end else begin
            quiescent_q <= fw_quiescent_q && !busy && !start_q &&
                !command_accept && !arm_event && !firmware_active;
            if (!run) begin seen_run_low_q <= 1; end
            if (arm_event) begin
                armed_q <= 1;
                restart_q <= 0;
                seen_run_low_q <= 0;
                fw_quiescent_q <= 0;
            end
            if (!owner) begin armed_q <= 0; end
            if (!run && !armed_q && quiescent_q) begin stop_ack_q <= stop_sync_q[1]; end
            if (command_accept || firmware_active) begin fw_quiescent_q <= 0; end
            if (firmware_ready) begin
                boot_ready_q <= 1;
                fw_quiescent_q <= 1;
            end
            if (firmware_quiesce) begin
                fw_quiescent_q <= 1;
                armed_q <= 0;
            end
            if (firmware_fault) begin
                fault_q <= 1;
                fw_quiescent_q <= 1;
                armed_q <= 0;
            end
            if (!cpu_rst_ni) begin
                armed_q <= 0;
                restart_q <= 1;
                boot_ready_q <= 0;
                fw_quiescent_q <= 1;
                seen_run_low_q <= 0;
                fault_q <= 0;
            end
        end
    end

    // Command payload and sticky completion data have one owner. start_q is
    // a pulse one cycle before the engine snapshots this stable payload.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            half_period_q <= MinHalf;
            register_q <= 0;
            tx_q <= 0;
            rx_q <= 0;
            device_q <= 0;
            read_q <= 0;
            start_q <= 0;
            done_q <= 0;
            nack_q <= 0;
            timeout_q <= 0;
            rejected_q <= 0;
        end else begin
            start_q <= command_accept;
            if (full_write && !busy && !start_q) begin
                case (addr_i[7:0])
                    8'h0c: begin
                        if (wdata_i >= MinHalfPeriod && wdata_i <= 65535) begin
                            half_period_q <= wdata_i[15:0];
                        end
                    end
                    8'h14: begin register_q <= wdata_i[15:0]; end
                    8'h18: begin tx_q <= wdata_i[7:0]; end
                    default: begin end
                endcase
            end
            if (done) begin
                done_q <= 1;
                nack_q <= nack;
                timeout_q <= timed_out;
                rx_q <= rx;
            end
            if (command_write && !command_accept) begin rejected_q <= 1; end
            if (command_accept) begin
                device_q <= wdata_i[14:8];
                read_q <= wdata_i[1];
                done_q <= 0;
                nack_q <= 0;
                timeout_q <= 0;
                rejected_q <= 0;
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rvalid_o <= 0;
            rdata_o <= 0;
            err_o <= 0;
        end else begin
            rvalid_o <= access;
            err_o <= 0;
            if (access) begin
                rdata_o <= 0;
                if (!aligned_access || (we_i && be_i != 4'hf)) begin
                    err_o <= 1;
                end else if (we_i) begin
                    case (addr_i[7:0])
                        8'h0c: begin
                            if (wdata_i < MinHalfPeriod || wdata_i > 65535 || busy || start_q) begin err_o <= 1; end
                        end
                        8'h10: begin err_o <= !command_accept; end
                        8'h14, 8'h18: begin err_o <= busy || start_q; end
                        8'h1c: begin
                            err_o <= !(firmware_ready || firmware_active || firmware_quiesce || firmware_fault);
                        end
                        default: begin err_o <= 1; end
                    endcase
                end else begin
                    case (addr_i[7:0])
                        8'h00: begin rdata_o <= 32'h53454e31; end
                        8'h04: begin rdata_o <= ticks_q; end
                        8'h08: begin
                            rdata_o <= {23'b0, restart_q, rejected_q, timeout_q,
                                nack_q, done_q, busy, grant_o, owner, run};
                        end
                        8'h0c: begin rdata_o <= {16'b0, half_period_q}; end
                        8'h14: begin rdata_o <= {16'b0, register_q}; end
                        8'h18: begin rdata_o <= {24'b0, rx_q}; end
                        8'h1c: begin rdata_o <= status_o; end
                        default: begin err_o <= 1; end
                    endcase
                end
            end
        end
    end
endmodule
