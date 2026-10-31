module xpm_memory_tdpram #(
parameter ADDR_WIDTH_A=16, ADDR_WIDTH_B=16, AUTO_SLEEP_TIME=0, BYTE_WRITE_WIDTH_A=8, BYTE_WRITE_WIDTH_B=8, CLOCKING_MODE="common_clock", ECC_MODE="no_ecc", MEMORY_INIT_FILE="none", MEMORY_INIT_PARAM="0", MEMORY_OPTIMIZATION="true", MEMORY_PRIMITIVE="block", MEMORY_SIZE=2097152, MESSAGE_CONTROL=0, READ_DATA_WIDTH_A=32, READ_DATA_WIDTH_B=32, READ_LATENCY_A=1, READ_LATENCY_B=1, READ_RESET_VALUE_A="0", READ_RESET_VALUE_B="0", RST_MODE_A="SYNC", RST_MODE_B="SYNC", SIM_ASSERT_CHK=0, USE_EMBEDDED_CONSTRAINT=0, USE_MEM_INIT=0, WAKEUP_TIME="disable_sleep", WRITE_DATA_WIDTH_A=32, WRITE_DATA_WIDTH_B=32, WRITE_MODE_A="read_first", WRITE_MODE_B="read_first"
)(input clka,clkb,rsta,rstb,ena,enb,regcea,regceb,sleep,injectsbiterra,injectdbiterra,injectsbiterrb,injectdbiterrb,input [ADDR_WIDTH_A-1:0] addra,input [ADDR_WIDTH_B-1:0] addrb,input [31:0] dina,dinb,input [3:0] wea,web,output logic [31:0] douta,doutb,output sbiterra,dbiterra,sbiterrb,dbiterrb);
logic [31:0] mem [0:65535]; assign {sbiterra,dbiterra,sbiterrb,dbiterrb}=0;
always @(posedge clka) if(ena) begin douta<=mem[addra]; for(integer i=0;i<4;i++) if(wea[i]) mem[addra][i*8+:8]<=dina[i*8+:8]; end
always @(posedge clkb) if(enb) begin doutb<=mem[addrb]; for(integer i=0;i<4;i++) if(web[i]) mem[addrb][i*8+:8]<=dinb[i*8+:8]; end
endmodule
