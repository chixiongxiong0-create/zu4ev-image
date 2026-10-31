// SPDX-License-Identifier: Apache-2.0
// Real pinned OpenTitan IP; all ports use clk_i/rst_ni.
module ibex_opentitan_peripherals (
  input logic clk_i, rst_ni,
  input logic req_i, we_i,
  input logic [31:0] addr_i, wdata_i,
  input logic [3:0] be_i,
  output logic gnt_o, rvalid_o, err_o,
  output logic [31:0] rdata_o,
  output logic integrity_error_o, alert_o, irq_timer_o, irq_external_o, irq_uart_o,
  input logic [31:0] gpio_i,
  output logic [31:0] gpio_o, gpio_oe_o,
  input logic i2c_scl_i, i2c_sda_i,
  output logic i2c_scl_o, i2c_scl_oe_o, i2c_sda_o, i2c_sda_oe_o,
  input logic uart_rx_i,
  output logic uart_tx_o
);
  tlul_pkg::tl_h2d_t tl_host, tl_devices [4];
  tlul_pkg::tl_d2h_t tl_response, tl_responses [4];
  logic [2:0] select_device;
  logic [14:0] i2c_irq;
  logic [8:0] uart_irq;
  logic [31:0] gpio_irq;
  prim_alert_pkg::alert_tx_t [0:0] alerts [4];
  assign alert_o = alerts[0][0].alert_p | alerts[1][0].alert_p |
                   alerts[2][0].alert_p | alerts[3][0].alert_p;
  assign irq_external_o = (|i2c_irq) | (|gpio_irq);
  assign irq_uart_o = |uart_irq;
  always_comb begin
    select_device = 3'd4;
    case (tl_host.a_address[31:16])
      16'h4000: select_device = 3'd0;
      16'h4001: select_device = 3'd1;
      16'h4002: select_device = 3'd2;
      16'h4003: select_device = 3'd3;
      default: ;
    endcase
  end
  ibex_opentitan_tlul_bridge u_bridge (
    .clk_i, .rst_ni, .req_i, .we_i, .addr_i, .wdata_i, .be_i,
    .gnt_o, .rvalid_o, .rdata_o, .err_o, .integrity_error_o,
    .tl_o(tl_host), .tl_i(tl_response)
  );
  tlul_socket_1n #(.N(4)) u_socket (
    .clk_i, .rst_ni, .tl_h_i(tl_host), .tl_h_o(tl_response),
    .tl_d_o(tl_devices), .tl_d_i(tl_responses), .dev_select_i(select_device)
  );
  rv_timer #(.AlertAsyncOn('0)) u_rv_timer (
    .clk_i,
    .rst_ni,
    .tl_i(tl_devices[0]),
    .tl_o(tl_responses[0]),
    .alert_rx_i('{default: prim_alert_pkg::ALERT_RX_DEFAULT}),
    .alert_tx_o(alerts[0]),
    .racl_policies_i('0),
    .racl_error_o(),
    .intr_timer_expired_hart0_timer0_o(irq_timer_o)
  );
  i2c #(.AlertAsyncOn('0)) u_i2c (
    .clk_i,
    .rst_ni,
    .tl_i(tl_devices[1]),
    .tl_o(tl_responses[1]),
    .alert_rx_i('{default: prim_alert_pkg::ALERT_RX_DEFAULT}),
    .alert_tx_o(alerts[1]),
    .racl_policies_i('0),
    .racl_error_o(),
    .ram_cfg_i('0),
    .ram_cfg_o(),
    .cio_scl_i(i2c_scl_i),
    .cio_scl_o(i2c_scl_o),
    .cio_scl_en_o(i2c_scl_oe_o),
    .cio_sda_i(i2c_sda_i),
    .cio_sda_o(i2c_sda_o),
    .cio_sda_en_o(i2c_sda_oe_o),
    .lsio_trigger_o(),
    .intr_fmt_threshold_o(i2c_irq[0]),
    .intr_rx_threshold_o(i2c_irq[1]),
    .intr_acq_threshold_o(i2c_irq[2]),
    .intr_rx_overflow_o(i2c_irq[3]),
    .intr_controller_halt_o(i2c_irq[4]),
    .intr_scl_interference_o(i2c_irq[5]),
    .intr_sda_interference_o(i2c_irq[6]),
    .intr_stretch_timeout_o(i2c_irq[7]),
    .intr_sda_unstable_o(i2c_irq[8]),
    .intr_cmd_complete_o(i2c_irq[9]),
    .intr_tx_stretch_o(i2c_irq[10]),
    .intr_tx_threshold_o(i2c_irq[11]),
    .intr_acq_stretch_o(i2c_irq[12]),
    .intr_unexp_stop_o(i2c_irq[13]),
    .intr_host_timeout_o(i2c_irq[14])
  );
  uart #(.AlertAsyncOn('0)) u_uart (
    .clk_i,
    .rst_ni,
    .tl_i(tl_devices[2]),
    .tl_o(tl_responses[2]),
    .alert_rx_i('{default: prim_alert_pkg::ALERT_RX_DEFAULT}),
    .alert_tx_o(alerts[2]),
    .racl_policies_i('0),
    .racl_error_o(),
    .cio_rx_i(uart_rx_i),
    .cio_tx_o(uart_tx_o),
    .cio_tx_en_o(),
    .lsio_trigger_o(),
    .intr_tx_watermark_o(uart_irq[0]),
    .intr_tx_empty_o(uart_irq[1]),
    .intr_rx_watermark_o(uart_irq[2]),
    .intr_tx_done_o(uart_irq[3]),
    .intr_rx_overflow_o(uart_irq[4]),
    .intr_rx_frame_err_o(uart_irq[5]),
    .intr_rx_break_err_o(uart_irq[6]),
    .intr_rx_timeout_o(uart_irq[7]),
    .intr_rx_parity_err_o(uart_irq[8])
  );
  gpio #(.AlertAsyncOn('0), .GpioAsHwStrapsEn(1'b0), .RaclErrorRsp(1'b0)) u_gpio (
    .clk_i,
    .rst_ni,
    .tl_i(tl_devices[3]),
    .tl_o(tl_responses[3]),
    .alert_rx_i('{default: prim_alert_pkg::ALERT_RX_DEFAULT}),
    .alert_tx_o(alerts[3]),
    .racl_policies_i('0),
    .racl_error_o(),
    .strap_en_i(1'b0),
    .sampled_straps_o(),
    .intr_gpio_o(gpio_irq),
    .cio_gpio_i(gpio_i),
    .cio_gpio_o(gpio_o),
    .cio_gpio_en_o(gpio_oe_o)
  );
endmodule
