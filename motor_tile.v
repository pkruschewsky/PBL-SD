module motor_tile (
	input [13:0] endereco,
	input clk,
	input read,
	output [7:0] dado_saida
	);
	
	rom_tiles tiles_pre_def(
	.address(endereco),
	.clock(clk),
	.rden(read),
	.q(dado_saida)
	);

endmodule