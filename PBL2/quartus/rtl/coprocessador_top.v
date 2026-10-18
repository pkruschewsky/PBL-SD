// ============================================================================
// coprocessador_top.v
// Topo do coprocessador grafico: nucleo programavel + unidades graficas + VGA.
//
//   ARM --PIOs--> [nucleo_coprocessador] --barramento grafico--> motores
//                  (busca + UC + datapath)                         |
//                          ^                                       v
//                    [unidade_quadro] <--v_ativo-- [vga_driver] <-- [compositor]
//
// Unidades graficas (comandadas pelas instrucoes executadas no nucleo):
//   motor_background  : tilemap 40x30 + scroll
//   motor_sprites     : 32 sprites 16x16 (escrita por campo, BACK)
//   4 x rasterizador_poligonos : slots 0 a 3 (RECT ou TRI); slot 0 na frente
//   compositor        : sprite frente > poligono > sprite tras > fundo
//   restaura_tilemap  : no reset, copia o mapa inicial (ROM) de volta para a
//                       RAM do tilemap; o nucleo espera em reset ate terminar
//
// Compositor, unidade de quadro e VGA funcionam o tempo todo, independente
// das instrucoes (requisito do PBL).
//
// ALINHAMENTO DAS CAMADAS (latencia desde next_x/next_y):
//   fundo   : RAM do tilemap (1) + ROM de tiles (2)  = 3 ciclos
//   sprites : ROM de sprites (2) + 1 registrador     = 3 ciclos
//   poligono: combinacional (0) + 3 registradores    = 3 ciclos
// ============================================================================
`timescale 1ns/1ps
module coprocessador_top (
    input  wire        CLOCK_50,
    input  wire        reset_externo,     // ativo alto (ex.: ~KEY[0])

    // ---- interface MMIO com o ARM (PIOs) ----
    input  wire [31:0] pio_instr,
    input  wire [1:0]  pio_ctrl,          // [0] valid, [1] reset do coprocessador
    output wire [31:0] pio_status,

    // ---- VGA ----
    output wire [7:0]  VGA_R,
    output wire [7:0]  VGA_G,
    output wire [7:0]  VGA_B,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire        VGA_CLK,
    output wire        VGA_SYNC_N,
    output wire        VGA_BLANK_N,

    // ---- depuracao (LEDs / displays) ----
    output wire [31:0] dbg_ir,
    output wire [15:0] dbg_quadros
);

    // ------------------------------------------------------------------
    // Clock de 25 MHz (CLOCK_50 / 2). O valor inicial e o de power-up.
    // ------------------------------------------------------------------
    reg clk25 = 1'b0;
    always @(posedge CLOCK_50) clk25 <= ~clk25;

    // ------------------------------------------------------------------
    // Reset: botao da placa OU bit 1 do pio_ctrl, sincronizado em clk25
    // ------------------------------------------------------------------
    reg rst_s1 = 1'b1, rst_s2 = 1'b1;
    always @(posedge clk25) begin
        rst_s1 <= reset_externo | pio_ctrl[1];
        rst_s2 <= rst_s1;
    end
    wire reset = rst_s2;

    // ------------------------------------------------------------------
    // Restauracao do tilemap: depois de qualquer reset, copia o mapa
    // inicial (ROM) para a RAM do tilemap (~48 us). Enquanto copia, o
    // nucleo fica em reset e o bit busy do status fica em 1.
    // ------------------------------------------------------------------
    wire [10:0] rest_rom_addr;  wire [7:0] rest_rom_data;
    wire        rest_we;        wire [10:0] rest_addr;  wire [7:0] rest_data;
    wire        restaurando;

    rom_mapa_inicial u_rom_mapa (
        .address(rest_rom_addr), .clock(clk25), .rden(1'b1), .q(rest_rom_data)
    );
    restaura_tilemap u_restaura (
        .clk(clk25), .reset(reset),
        .rom_addr(rest_rom_addr), .rom_data(rest_rom_data),
        .we(rest_we), .wr_addr(rest_addr), .wr_data(rest_data),
        .ocupado(restaurando)
    );
    wire reset_nucleo = restaurando;            // inclui o proprio reset

    // ------------------------------------------------------------------
    // VGA e unidade de quadro
    // ------------------------------------------------------------------
    wire [9:0] next_x, next_y;
    wire       v_ativo;
    wire [7:0] cor_final;

    vga_driver u_vga (
        .clock(clk25), .reset(reset), .color_in(cor_final),
        .next_x(next_x), .next_y(next_y),
        .hsync(VGA_HS), .vsync(VGA_VS),
        .red(VGA_R), .green(VGA_G), .blue(VGA_B),
        .sync(VGA_SYNC_N), .clk(VGA_CLK), .blank(VGA_BLANK_N),
        .v_ativo(v_ativo)
    );

    wire vblank, inicio_vblank;
    unidade_quadro u_quadro (
        .clk(clk25), .reset(reset), .v_ativo(v_ativo),
        .vblank(vblank), .inicio_vblank(inicio_vblank), .contador_quadros(dbg_quadros)
    );

    // ------------------------------------------------------------------
    // Nucleo programavel
    // ------------------------------------------------------------------
    wire        tm_wr_en;   wire [10:0] tm_wr_addr;  wire [7:0] tm_wr_data;
    wire [8:0]  scroll_x;   wire [7:0]  scroll_y;
    wire [8:0]  p0_x0, p0_x1, p0_x2, p1_x0, p1_x1, p1_x2, p2_x0, p2_x1, p2_x2, p3_x0, p3_x1, p3_x2;
    wire [7:0]  p0_y0, p0_y1, p0_y2, p1_y0, p1_y1, p1_y2, p2_y0, p2_y1, p2_y2, p3_y0, p3_y1, p3_y2;
    wire [1:0]  p0_tipo, p1_tipo, p2_tipo, p3_tipo;
    wire [7:0]  p0_cor, p1_cor, p2_cor, p3_cor;
    wire        spr_wr_pos, spr_wr_attr;
    wire [4:0]  spr_idx;
    wire [8:0]  spr_x, spr_cur_x;
    wire [7:0]  spr_y, spr_cur_y;
    wire [11:0] spr_attr;

    wire [31:0] status_nucleo;
    assign pio_status = status_nucleo | {31'd0, restaurando};   // busy = 1 enquanto restaura

    nucleo_coprocessador u_nucleo (
        .clk(clk25), .reset(reset_nucleo),
        .pio_instr(pio_instr), .pio_valid(pio_ctrl[0]), .status(status_nucleo),
        .vblank(vblank), .inicio_vblank(inicio_vblank),
        .tm_wr_en(tm_wr_en), .tm_wr_addr(tm_wr_addr), .tm_wr_data(tm_wr_data),
        .scroll_x(scroll_x), .scroll_y(scroll_y),
        .p0_x0(p0_x0), .p0_x1(p0_x1), .p0_x2(p0_x2), .p0_y0(p0_y0), .p0_y1(p0_y1), .p0_y2(p0_y2),
        .p0_tipo(p0_tipo), .p0_cor(p0_cor),
        .p1_x0(p1_x0), .p1_x1(p1_x1), .p1_x2(p1_x2), .p1_y0(p1_y0), .p1_y1(p1_y1), .p1_y2(p1_y2),
        .p1_tipo(p1_tipo), .p1_cor(p1_cor),
        .p2_x0(p2_x0), .p2_x1(p2_x1), .p2_x2(p2_x2), .p2_y0(p2_y0), .p2_y1(p2_y1), .p2_y2(p2_y2),
        .p2_tipo(p2_tipo), .p2_cor(p2_cor),
        .p3_x0(p3_x0), .p3_x1(p3_x1), .p3_x2(p3_x2), .p3_y0(p3_y0), .p3_y1(p3_y1), .p3_y2(p3_y2),
        .p3_tipo(p3_tipo), .p3_cor(p3_cor),
        .spr_wr_pos(spr_wr_pos), .spr_wr_attr(spr_wr_attr), .spr_idx(spr_idx),
        .spr_x(spr_x), .spr_y(spr_y), .spr_attr(spr_attr),
        .spr_cur_x(spr_cur_x), .spr_cur_y(spr_cur_y),
        .ir_atual(dbg_ir)
    );

    // ------------------------------------------------------------------
    // Memorias de padroes (ROMs de tiles e de sprites)
    // ------------------------------------------------------------------
    wire [13:0] bg_rom_addr;   wire [7:0] bg_rom_data;
    wire [12:0] spr_rom_addr;  wire [7:0] spr_rom_data;

    motor_tile u_rom_cenario (
        .endereco(bg_rom_addr), .clk(clk25), .read(1'b1), .dado_saida_tiles(bg_rom_data)
    );
    rom_sprites_inst u_rom_sprites (
        .endereco(spr_rom_addr), .clk(clk25), .read(1'b1), .dado_saida_sprites(spr_rom_data)
    );

    // ------------------------------------------------------------------
    // Motor de background                                -> 3 ciclos
    // A porta de escrita do tilemap e do restaurador durante a copia e do
    // nucleo no resto do tempo (os dois nunca escrevem ao mesmo tempo).
    // ------------------------------------------------------------------
    wire        bg_we   = restaurando ? rest_we   : tm_wr_en;
    wire [10:0] bg_addr = restaurando ? rest_addr : tm_wr_addr;
    wire [7:0]  bg_data = restaurando ? rest_data : tm_wr_data;
    wire [7:0] bg_color;
    motor_background u_bg (
        .clk(clk25), .next_x(next_x), .next_y(next_y),
        .scroll_x(scroll_x), .scroll_y(scroll_y),
        .tm_wr_en(bg_we), .tm_wr_addr(bg_addr), .tm_wr_data(bg_data),
        .rom_addr(bg_rom_addr), .rom_data(bg_rom_data),
        .cor_pixel(bg_color)
    );

    // ------------------------------------------------------------------
    // Motor de sprites                                   -> 2 ciclos (+1 abaixo)
    // ------------------------------------------------------------------
    wire       spr_ativo_2, spr_back_2;
    wire [7:0] spr_color_2;
    motor_sprites u_sprites (
        .clk(clk25), .reset(reset), .next_x(next_x), .next_y(next_y),
        .pos_we(spr_wr_pos), .attr_we(spr_wr_attr), .wr_idx(spr_idx),
        .wr_x(spr_x), .wr_y(spr_y), .wr_attr(spr_attr),
        .rd_idx(spr_idx), .rd_x(spr_cur_x), .rd_y(spr_cur_y),
        .rom_addr(spr_rom_addr), .rom_data(spr_rom_data),
        .sprite_ativo(spr_ativo_2), .sprite_color(spr_color_2), .sprite_back(spr_back_2)
    );

    // ------------------------------------------------------------------
    // Rasterizadores: 1 por slot                         -> 0 ciclos (+3 abaixo)
    // modo_ativo = tipo do POLY_CFG: 0 OFF, 1 RECT, 2 TRI
    // ------------------------------------------------------------------
    wire       hit0, hit1, hit2, hit3;
    wire [7:0] cor0, cor1, cor2, cor3;
    rasterizador_poligonos u_slot0 (
        .clk(clk25), .jogo_x(next_x[9:1]), .jogo_y(next_y[8:1]), .modo_ativo(p0_tipo),
        .x0(p0_x0), .y0({1'b0, p0_y0}), .x1(p0_x1), .y1({1'b0, p0_y1}), .x2(p0_x2), .y2({1'b0, p0_y2}),
        .cor_indice(p0_cor), .poly_ativo(hit0), .poly_color(cor0)
    );
    rasterizador_poligonos u_slot1 (
        .clk(clk25), .jogo_x(next_x[9:1]), .jogo_y(next_y[8:1]), .modo_ativo(p1_tipo),
        .x0(p1_x0), .y0({1'b0, p1_y0}), .x1(p1_x1), .y1({1'b0, p1_y1}), .x2(p1_x2), .y2({1'b0, p1_y2}),
        .cor_indice(p1_cor), .poly_ativo(hit1), .poly_color(cor1)
    );
    rasterizador_poligonos u_slot2 (
        .clk(clk25), .jogo_x(next_x[9:1]), .jogo_y(next_y[8:1]), .modo_ativo(p2_tipo),
        .x0(p2_x0), .y0({1'b0, p2_y0}), .x1(p2_x1), .y1({1'b0, p2_y1}), .x2(p2_x2), .y2({1'b0, p2_y2}),
        .cor_indice(p2_cor), .poly_ativo(hit2), .poly_color(cor2)
    );
    rasterizador_poligonos u_slot3 (
        .clk(clk25), .jogo_x(next_x[9:1]), .jogo_y(next_y[8:1]), .modo_ativo(p3_tipo),
        .x0(p3_x0), .y0({1'b0, p3_y0}), .x1(p3_x1), .y1({1'b0, p3_y1}), .x2(p3_x2), .y2({1'b0, p3_y2}),
        .cor_indice(p3_cor), .poly_ativo(hit3), .poly_color(cor3)
    );
    // prioridade: slot 0 > slot 1 > slot 2 > slot 3; cor 0 = transparente
    wire       vis0 = hit0 && (p0_cor != 8'd0);
    wire       vis1 = hit1 && (p1_cor != 8'd0);
    wire       vis2 = hit2 && (p2_cor != 8'd0);
    wire       vis3 = hit3 && (p3_cor != 8'd0);
    wire       poly_ativo_0 = vis0 | vis1 | vis2 | vis3;
    wire [7:0] poly_cor_0   = vis0 ? cor0 : vis1 ? cor1 : vis2 ? cor2 : cor3;

    // ------------------------------------------------------------------
    // Pipeline de alinhamento (todas as camadas chegam com 3 ciclos)
    // ------------------------------------------------------------------
    reg        spr_ativo_3, spr_back_3;
    reg [7:0]  spr_color_3;
    reg        pa1, pa2, pa3;
    reg [7:0]  pc1, pc2, pc3;
    always @(posedge clk25) begin
        spr_ativo_3 <= spr_ativo_2;  spr_back_3 <= spr_back_2;  spr_color_3 <= spr_color_2;
        pa1 <= poly_ativo_0;  pa2 <= pa1;  pa3 <= pa2;
        pc1 <= poly_cor_0;    pc2 <= pc1;  pc3 <= pc2;
    end

    // ------------------------------------------------------------------
    // Compositor
    // ------------------------------------------------------------------
    compositor u_comp (
        .bg_color(bg_color),
        .poly_ativo(pa3), .poly_color(pc3),
        .sprite_ativo(spr_ativo_3), .sprite_color(spr_color_3), .sprite_back(spr_back_3),
        .cor_final(cor_final)
    );

endmodule
