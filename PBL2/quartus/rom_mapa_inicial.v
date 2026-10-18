// ============================================================================
// rom_mapa_inicial.v - ROM (altsyncram, Cyclone V) com o MAPA INICIAL do tilemap
// 1200 posicoes x 8 bits, conteudo em mapa_inicial.mif (o mesmo da RAM do tilemap).
// Endereco e saida registrados = 2 ciclos de latencia (igual as ROMs de tiles e de sprites).
// Usada pelo restaura_tilemap para recolocar o fundo original apos o reset.
// Feita a partir da rom_cenario_tile.v (gerada pelo IP Catalog "ROM: 1-PORT").
// ============================================================================
// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
module rom_mapa_inicial (
	address,
	clock,
	rden,
	q);

	input	[10:0]  address;
	input	  clock;
	input	  rden;
	output	[7:0]  q;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_off
`endif
	tri1	  clock;
	tri1	  rden;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_on
`endif

	wire [7:0] sub_wire0;
	wire [7:0] q = sub_wire0[7:0];

	altsyncram	altsyncram_component (
				.address_a (address),
				.clock0 (clock),
				.rden_a (rden),
				.q_a (sub_wire0),
				.aclr0 (1'b0),
				.aclr1 (1'b0),
				.address_b (1'b1),
				.addressstall_a (1'b0),
				.addressstall_b (1'b0),
				.byteena_a (1'b1),
				.byteena_b (1'b1),
				.clock1 (1'b1),
				.clocken0 (1'b1),
				.clocken1 (1'b1),
				.clocken2 (1'b1),
				.clocken3 (1'b1),
				.data_a ({8{1'b1}}),
				.data_b (1'b1),
				.eccstatus (),
				.q_b (),
				.rden_b (1'b1),
				.wren_a (1'b0),
				.wren_b (1'b0));
	defparam
		altsyncram_component.address_aclr_a = "NONE",
		altsyncram_component.clock_enable_input_a = "BYPASS",
		altsyncram_component.clock_enable_output_a = "BYPASS",
		altsyncram_component.init_file = "mapa_inicial.mif",
		altsyncram_component.intended_device_family = "Cyclone V",
		altsyncram_component.lpm_hint = "ENABLE_RUNTIME_MOD=NO",
		altsyncram_component.lpm_type = "altsyncram",
		altsyncram_component.numwords_a = 1200,
		altsyncram_component.operation_mode = "ROM",
		altsyncram_component.outdata_aclr_a = "NONE",
		altsyncram_component.outdata_reg_a = "CLOCK0",
		altsyncram_component.ram_block_type = "M10K",
		altsyncram_component.widthad_a = 11,
		altsyncram_component.width_a = 8,
		altsyncram_component.width_byteena_a = 1;


endmodule

