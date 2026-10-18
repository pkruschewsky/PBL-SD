// ============================================================================
// motor_tilemap.v
// Interface de acesso ao tilemap (40x30 posicoes): leitura continua para o
// video e escrita pontual (usada pela MEF de demonstracao para editar tiles).
// ============================================================================
module motor_tilemap (
	input  [10:0] endereco_leitura,   // posicao do tilemap sendo lida (video)
	input  [10:0] endereco_escrita,   // posicao do tilemap sendo escrita
	input  [7:0]  dado_escrita,       // tile_id a gravar
	input         escreve,            // habilita escrita
	input         clk,
	output [7:0]  tile_id             // tile_id lido (1 ciclo de latencia)
	);

	ram_tilemap tilemap_pre_def (
	.clock     (clk),
	.data      (dado_escrita),
	.rdaddress (endereco_leitura),
	.wraddress (endereco_escrita),
	.wren      (escreve),
	.q         (tile_id)
	);
endmodule
