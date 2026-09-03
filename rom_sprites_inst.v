// ============================================================================
// rom_sprites_inst.v
// Interface de leitura da ROM de sprites (1 porta): recebe o endereco
// calculado pelo motor_sprites e devolve o dado de pixel correspondente.
// ============================================================================
module rom_sprites_inst (
	input [12:0] endereco,
	input clk,
	input read,
	output [7:0] dado_saida_sprites
	);

	rom_sprites rom_dos_sprites(
	.address(endereco),
	.clock(clk),
	.rden(read),
	.q(dado_saida_sprites)
	);
	
endmodule
