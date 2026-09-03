// ============================================================================
// motor_tile.v
// Interface de leitura da ROM de cenario (1 porta): recebe o endereco
// calculado pelo motor_background e devolve o dado de pixel correspondente.
// ============================================================================
module motor_tile (
	input [13:0] endereco,
	input clk,
	input read,
	output [7:0] dado_saida_tiles
	);
	
	rom_cenario_tile tiles_pre_def(
	.address(endereco),
	.clock(clk),
	.rden(read),
	.q(dado_saida_tiles)
	);

endmodule
