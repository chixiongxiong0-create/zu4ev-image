`timescale 1ns/1ps
// Behavioral open-drain SC130 register target for offline integration tests.
module sc130_sensor_model(inout wire scl,inout wire sda);
  reg drive_low=0, active=0, read_mode=0, ack_phase=0, ack_clock=0, send_mode=0, master_ack=0, force_nack=0;
  reg [7:0] shift=0, data_out=0; reg [15:0] reg_addr=0;
  reg [7:0] registers [0:65535]; integer bits=0, byte_number=0, writes=0, reads=0, starts=0, stops=0;
  assign sda=drive_low ? 1'b0 : 1'bz;
  initial begin
    registers['h3107]=8'h01; registers['h3108]=8'h30; registers['h0100]=8'h01;
    registers['h320e]=8'h04; registers['h320f]=8'h65;
    registers['h3e01]=8'h10; registers['h3e02]=8'h00;
    registers['h3e08]=8'h03; registers['h3e09]=8'h20; registers['h3e03]=8'h01;
  end
  always @(negedge sda) if(scl===1'b1 && !drive_low) begin
    active=1;bits=0;byte_number=0;ack_phase=0;ack_clock=0;send_mode=0;master_ack=0; starts=starts+1;
  end
  always @(posedge sda) if(scl===1'b1 && active && !drive_low) begin
    active=0;drive_low=0;stops=stops+1;
  end
  always @(posedge scl) if(active) begin
    if(ack_phase) ack_clock=1;
    else if(master_ack) begin
      if(sda!==1'b1) $fatal(1,"sensor expected master NACK");
      master_ack=0;
    end else if(send_mode) begin
      bits=bits+1;
    end else begin
      shift={shift[6:0],sda};bits=bits+1;
      if(bits==8) begin
        if(byte_number==0) begin
          if(shift[7:1]!==7'h30) $fatal(1,"unexpected I2C device %h",shift);
          read_mode=shift[0];
        end else if(!read_mode && byte_number==1) reg_addr[15:8]=shift;
        else if(!read_mode && byte_number==2) reg_addr[7:0]=shift;
        else if(!read_mode) begin registers[reg_addr]=shift;writes=writes+1;end
        ack_phase=1;ack_clock=0;bits=0;byte_number=byte_number+1;
      end
    end
  end
  always @(negedge scl) if(active) begin
    if(ack_phase && !ack_clock) drive_low=!force_nack;
    else if(ack_phase && ack_clock) begin
      drive_low=0;ack_phase=0;ack_clock=0;
      if(read_mode && byte_number==1) begin
        data_out=registers[reg_addr]; if(^data_out===1'bx) $fatal(1,"unknown sensor register %h",reg_addr);
        reads=reads+1;send_mode=1;bits=0;drive_low=~data_out[7];
      end
    end else if(send_mode) begin
      if(bits==8) begin drive_low=0;send_mode=0;master_ack=1;bits=0;end
      else drive_low=~data_out[7-bits];
    end
  end
endmodule
