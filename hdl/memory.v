// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on

//*****************************************************
//* Модуль ROM рамером 8к*16 с монитором мс1201-055
//*****************************************************

module rom_monitor(
	input				wb_clk_i,
	input	 [11:0]	adr_i,
   output [15:0]	wb_dat_o,
	input				wb_cyc_i,
	input				wb_stb_i,
	output			wb_ack_o
);
reg [1:0]ack;

rom055 hrom(
	.address(adr_i),
	.clock(wb_clk_i),
	.q(wb_dat_o)
);

// формирователь cигнала подверждения транзакции
assign wb_ack_o = wb_cyc_i & wb_stb_i & ack[1];

always @ (posedge wb_clk_i) 
begin
	ack[0] <= wb_cyc_i & wb_stb_i;
	ack[1] <= wb_cyc_i & ack[0];
end


endmodule

