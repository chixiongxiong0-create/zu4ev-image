// SPDX-License-Identifier: Apache-2.0
// One SC130 register transaction. Outputs are open-drain pull-low enables.
module ibex_sensor_i2c #(
    parameter int unsigned TimeoutCycles = 1000000,
    parameter int unsigned MinHalfPeriod = 125
)(
    input wire clk_i, rst_ni, start_i, read_i,
    input wire [6:0] device_i,
    input wire [15:0] register_i, half_period_i,
    input wire [7:0] wdata_i,
    input wire scl_i, sda_i,
    output logic scl_low_o, sda_low_o,
    output wire busy_o,
    output logic done_o, nack_o, timeout_o,
    output logic [7:0] rdata_o
);
    localparam logic [15:0] MinHalf = 16'(MinHalfPeriod);
    localparam logic [31:0] TimeoutLast = 32'(TimeoutCycles - 1);
    typedef enum logic [4:0] {
        ST_IDLE, ST_FREE, ST_START, ST_TX_LOW, ST_TX_HIGH,
        ST_ACK_LOW, ST_ACK_HIGH, ST_RESTART_LOW, ST_RESTART_HIGH, ST_RESTART,
        ST_RX_LOW, ST_RX_HIGH, ST_NACK_LOW, ST_NACK_HIGH,
        ST_STOP_LOW, ST_STOP_HIGH, ST_STOP_RELEASE
    } state_t;
    state_t state_q, state_d;
    logic read_q;
    logic [6:0] device_q;
    logic [15:0] register_q, half_period_q, phase_cycles_q;
    logic [7:0] wdata_q, shift_q;
    logic [2:0] bit_q, byte_q;
    logic [31:0] elapsed_q;
    logic invalid_state;
    (* ASYNC_REG = "TRUE" *) logic [1:0] scl_sync_q, sda_sync_q;
    wire scl_high = scl_sync_q[1];
    wire sda_high = sda_sync_q[1];
    wire high_phase = state_q == ST_FREE || state_q == ST_START ||
        state_q == ST_TX_HIGH || state_q == ST_ACK_HIGH ||
        state_q == ST_RESTART_HIGH || state_q == ST_RESTART ||
        state_q == ST_RX_HIGH || state_q == ST_NACK_HIGH ||
        state_q == ST_STOP_HIGH || state_q == ST_STOP_RELEASE;
    wire phase_ready = (!high_phase || scl_high) &&
        (state_q != ST_FREE || sda_high);
    wire phase_complete = phase_ready && phase_cycles_q == half_period_q - 16'd1;
    wire transaction_accept = state_q == ST_IDLE && start_i;
    wire transaction_timeout = busy_o && elapsed_q >= TimeoutLast;
    wire transaction_complete = state_q == ST_STOP_RELEASE && phase_complete;
    wire ack_complete = state_q == ST_ACK_HIGH && phase_complete;
    wire receive_complete = state_q == ST_RX_HIGH && phase_complete;
    assign busy_o = state_q != ST_IDLE;

    always_comb begin
        scl_low_o = 1'b0;
        sda_low_o = 1'b0;
        case (state_q)
            ST_START, ST_RESTART, ST_STOP_HIGH: begin
                sda_low_o = 1'b1;
            end
            ST_TX_LOW: begin
                scl_low_o = 1'b1;
                sda_low_o = ~shift_q[bit_q];
            end
            ST_TX_HIGH: begin
                sda_low_o = ~shift_q[bit_q];
            end
            ST_ACK_LOW, ST_RESTART_LOW, ST_RX_LOW, ST_NACK_LOW: begin
                scl_low_o = 1'b1;
            end
            ST_STOP_LOW: begin
                scl_low_o = 1'b1;
                sda_low_o = 1'b1;
            end
            default: begin end
        endcase
    end

    // Controller: each transition consumes a completed bus phase. The clock
    // timer remains stopped while an external device stretches SCL low.
    always_comb begin
        state_d = state_q;
        invalid_state = 1'b0;
        case (state_q)
            ST_IDLE: begin
                if (transaction_accept) begin state_d = ST_FREE; end
            end
            ST_FREE: begin
                if (phase_complete) begin state_d = ST_START; end
            end
            ST_START: begin
                if (phase_complete) begin state_d = ST_TX_LOW; end
            end
            ST_TX_LOW: begin
                if (phase_complete) begin state_d = ST_TX_HIGH; end
            end
            ST_TX_HIGH: begin
                if (phase_complete) begin
                    state_d = bit_q == 0 ? ST_ACK_LOW : ST_TX_LOW;
                end
            end
            ST_ACK_LOW: begin
                if (phase_complete) begin state_d = ST_ACK_HIGH; end
            end
            ST_ACK_HIGH: begin
                if (phase_complete) begin
                    if (sda_high) begin
                        state_d = ST_STOP_LOW;
                    end else begin
                        case (byte_q)
                            0, 1: begin state_d = ST_TX_LOW; end
                            2: begin state_d = read_q ? ST_RESTART_LOW : ST_TX_LOW; end
                            3: begin state_d = ST_STOP_LOW; end
                            4: begin state_d = ST_RX_LOW; end
                            default: begin state_d = ST_STOP_LOW; end
                        endcase
                    end
                end
            end
            ST_RESTART_LOW: begin
                if (phase_complete) begin state_d = ST_RESTART_HIGH; end
            end
            ST_RESTART_HIGH: begin
                if (phase_complete) begin state_d = ST_RESTART; end
            end
            ST_RESTART: begin
                if (phase_complete) begin state_d = ST_TX_LOW; end
            end
            ST_RX_LOW: begin
                if (phase_complete) begin state_d = ST_RX_HIGH; end
            end
            ST_RX_HIGH: begin
                if (phase_complete) begin
                    state_d = bit_q == 0 ? ST_NACK_LOW : ST_RX_LOW;
                end
            end
            ST_NACK_LOW: begin
                if (phase_complete) begin state_d = ST_NACK_HIGH; end
            end
            ST_NACK_HIGH: begin
                if (phase_complete) begin state_d = ST_STOP_LOW; end
            end
            ST_STOP_LOW: begin
                if (phase_complete) begin state_d = ST_STOP_HIGH; end
            end
            ST_STOP_HIGH: begin
                if (phase_complete) begin state_d = ST_STOP_RELEASE; end
            end
            ST_STOP_RELEASE: begin
                if (phase_complete) begin state_d = ST_IDLE; end
            end
            default: begin
                state_d = ST_IDLE;
                invalid_state = 1'b1;
            end
        endcase
        if (transaction_timeout) begin state_d = ST_IDLE; end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin state_q <= ST_IDLE; end
        else begin state_q <= state_d; end
    end
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            scl_sync_q <= 2'b11;
            sda_sync_q <= 2'b11;
        end else begin
            scl_sync_q <= {scl_sync_q[0], scl_i};
            sda_sync_q <= {sda_sync_q[0], sda_i};
        end
    end

    // Phase/transaction timers own cycle counts only. No implicit bit advance
    // is tied to a counter value without the named completed-phase event.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            phase_cycles_q <= 0;
            elapsed_q <= 0;
        end else begin
            if (!phase_ready || phase_complete || !busy_o || transaction_timeout) begin
                phase_cycles_q <= 0;
            end else begin
                phase_cycles_q <= phase_cycles_q + 16'd1;
            end
            if (!busy_o) begin elapsed_q <= 0; end
            else begin elapsed_q <= elapsed_q + 32'd1; end
        end
    end

    // Transaction metadata is captured once. The payload remains unchanged
    // until another IDLE start, including while the CPU is independently reset.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            read_q <= 0;
            device_q <= 0;
            register_q <= 0;
            wdata_q <= 0;
            half_period_q <= MinHalf;
        end else if (transaction_accept) begin
            read_q <= read_i;
            device_q <= device_i;
            register_q <= register_i;
            wdata_q <= wdata_i;
            half_period_q <= half_period_i < MinHalf ? MinHalf : half_period_i;
        end
    end

    // Byte selection/bit datapath, separate from protocol-state ownership.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            shift_q <= 0;
            bit_q <= 0;
            byte_q <= 0;
            rdata_o <= 0;
        end else if (transaction_accept) begin
            shift_q <= {device_i, 1'b0};
            bit_q <= 7;
            byte_q <= 0;
            rdata_o <= 0;
        end else if (phase_complete) begin
            if (state_q == ST_TX_HIGH && bit_q != 0) begin
                bit_q <= bit_q - 3'd1;
            end
            if (ack_complete && !sda_high) begin
                bit_q <= 7;
                case (byte_q)
                    0: begin shift_q <= register_q[15:8]; byte_q <= 1; end
                    1: begin shift_q <= register_q[7:0]; byte_q <= 2; end
                    2: begin shift_q <= wdata_q; byte_q <= 3; end
                    4: begin shift_q <= 0; end
                    default: begin end
                endcase
            end
            if (state_q == ST_RESTART) begin
                shift_q <= {device_q, 1'b1};
                byte_q <= 4;
                bit_q <= 7;
            end
            if (receive_complete) begin
                shift_q <= {shift_q[6:0], sda_high};
                if (bit_q == 0) begin rdata_o <= {shift_q[6:0], sda_high}; end
                else begin bit_q <= bit_q - 3'd1; end
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            done_o <= 0;
            nack_o <= 0;
            timeout_o <= 0;
        end else begin
            done_o <= transaction_complete || transaction_timeout || invalid_state;
            if (transaction_accept) begin
                nack_o <= 0;
                timeout_o <= 0;
            end
            if (ack_complete && sda_high) begin nack_o <= 1; end
            if (transaction_timeout || invalid_state) begin
                // A stuck SCL cannot carry STOP. State IDLE releases both pins.
                timeout_o <= 1;
            end
        end
    end
endmodule
