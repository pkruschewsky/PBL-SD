// ============================================================================
// top_video.v
// Integra fundo, sprites, poligonos e a maquina de estados de demonstracao
// (datapath multiplexado: as mesmas chaves e botoes controlam subsistemas
// diferentes, dependendo do estado selecionado em SW_in[9:8]).
// ============================================================================
module top_video (
    input  wire        CLOCK_50,    
    input  wire        reset,       
     
    input  wire        btn_write,    // KEY[1]: confirma/aplica o campo atual
    input  wire        KEY_move_dir, // KEY[2]: incrementa / move na direcao positiva
    input  wire        KEY_move_esq, // KEY[3]: decrementa / move na direcao negativa
    input  wire [9:0]  SW_in,        

    input  wire [8:0]  SW_scroll_x,  
    input  wire [7:0]  SW_scroll_y,

    output wire [7:0]  VGA_R,
    output wire [7:0]  VGA_G,
    output wire [7:0]  VGA_B,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire        VGA_CLK,
    output wire        VGA_SYNC_N,
    output wire        VGA_BLANK_N
);

    wire clk25;
    clock_divider u_clkdiv (
        .clk_in  (CLOCK_50),
        .reset   (reset),
        .clk_out (clk25)
    );

    wire [9:0] next_x, next_y;

    // =========================================================
    // SINCRONIZACAO E DETECCAO DE BORDA DOS BOTOES
    // =========================================================
    reg key1_r1, key1_r2, key2_r1, key2_r2, key3_r1, key3_r2;
    always @(posedge clk25) begin
        key1_r1 <= ~btn_write;      key1_r2 <= key1_r1;
        key2_r1 <= ~KEY_move_dir;   key2_r2 <= key2_r1; 
        key3_r1 <= ~KEY_move_esq;   key3_r2 <= key3_r1; 
    end
    wire key1_press = (key1_r1 & ~key1_r2); 
    wire key2_press = (key2_r1 & ~key2_r2); 
    wire key3_press = (key3_r1 & ~key3_r2); 
	 
	 // =========================================================
    // TIMER PARA MOVIMENTO/SCROLL CONTINUO
    // =========================================================
    // Gera um pulso periodico (~20 Hz em clk25 = 25 MHz) usado para
    // avancar o scroll enquanto o botao correspondente fica segurado
    reg [20:0] mov_timer;
    wire mov_tick = (mov_timer == 21'd1_250_000);

    always @(posedge clk25 or posedge reset) begin
        if (reset) mov_timer <= 21'd0;
        else if (mov_tick) mov_timer <= 21'd0;
        else mov_timer <= mov_timer + 21'd1;
    end

    // =========================================================
    // MAQUINA DE ESTADOS DE ROTEAMENTO (MEF DE DEMONSTRACAO)
    // =========================================================
    // SW_in[9:8] escolhe qual subsistema recebe os botoes e as chaves
    // de dados no momento: 00 = ocioso, 01 = fundo, 10 = poligonos,
    // 11 = sprites.
    wire       bg_upd; 
    wire [7:0] bg_d;
    wire       poly_upd, poly_dir, poly_esq; 
    wire [7:0] poly_d;
    wire       spr_upd, spr_dir, spr_esq; 
    wire [7:0] spr_d;

    mef_demonstracao u_mef (
        .estado_sel   (SW_in[9:8]),
        .btn_update   (key1_press),
        .btn_dir      (key2_press),
        .btn_esq      (key3_press),
        .chaves_dados (SW_in[7:0]),
        
        .bg_update    (bg_upd),      .bg_dados     (bg_d),
        .poly_update  (poly_upd),    .poly_dados   (poly_d),
        .poly_mov_dir (poly_dir),    .poly_mov_esq (poly_esq),
        .sprite_update(spr_upd),     .sprite_dados (spr_d),
        .sprite_mov_dir(spr_dir),    .sprite_mov_esq(spr_esq)
    );

	 // =========================================================
    // REGISTRADORES DE FUNDO E POLIGONOS
    // =========================================================
    reg ret_en, tri_en;
    reg [8:0] ret_x, tri_x;
    reg [7:0] ret_y, tri_y;
    reg [7:0] ret_cor, tri_cor;

    reg [10:0] bg_wr_addr;
    reg [8:0]  bg_scroll_x;
    reg [7:0]  bg_scroll_y;

    parameter [8:0] RET_W = 9'd80;   parameter [7:0] RET_H = 8'd40;
    parameter [8:0] TRI_BX = 9'd40;  parameter [7:0] TRI_HY = 8'd60; 

    always @(posedge clk25 or posedge reset) begin
        if (reset) begin
            ret_en <= 1'b1;  ret_x <= 9'd50;  ret_y <= 8'd50;  ret_cor <= 8'd5;
            tri_en <= 1'b1;  tri_x <= 9'd200; tri_y <= 8'd100; tri_cor <= 8'd15;
            
            bg_wr_addr  <= 11'd0;
            bg_scroll_x <= 9'd0;
            bg_scroll_y <= 8'd0;
        end else begin
            
		  // --- Estado 01: controle do fundo ---
            if (SW_in[9:8] == 2'b01) begin
                if (bg_d[7] == 1'b0) begin
                    // Edicao de tile: cada aperto move o cursor uma posicao
                    if (key2_press) bg_wr_addr <= bg_wr_addr + 11'd1;
                    if (key3_press) bg_wr_addr <= bg_wr_addr - 11'd1;
                end else begin
                    // Controle de scroll: avanca continuamente enquanto o botao fica segurado
                    if (bg_d[6] == 1'b0) begin
                        if (key2_r1 && mov_tick) bg_scroll_x <= bg_scroll_x + 9'd2;
                        if (key3_r1 && mov_tick) bg_scroll_x <= bg_scroll_x - 9'd2;
                    end else begin
                        if (key2_r1 && mov_tick) bg_scroll_y <= bg_scroll_y + 8'd2;
                        if (key3_r1 && mov_tick) bg_scroll_y <= bg_scroll_y - 8'd2;
                    end
                end
            end

            // --- Estado 10: controle dos poligonos ---
            if (poly_upd) begin
                if (poly_d[7] == 1'b0) ret_cor <= {2'b00, poly_d[5:0]}; 
                else                   tri_cor <= {2'b00, poly_d[5:0]}; 
            end
            else if (poly_dir) begin
                if (poly_d[7] == 1'b0) begin
                    if (poly_d[6] == 1'b0) ret_x <= ret_x + 9'd5; else ret_y <= ret_y + 8'd5;
                end else begin
                    if (poly_d[6] == 1'b0) tri_x <= tri_x + 9'd5; else tri_y <= tri_y + 8'd5;
                end
            end
            else if (poly_esq) begin
                if (poly_d[7] == 1'b0) begin
                    if (poly_d[6] == 1'b0) ret_x <= ret_x - 9'd5; else ret_y <= ret_y - 8'd5;
                end else begin
                    if (poly_d[6] == 1'b0) tri_x <= tri_x - 9'd5; else tri_y <= tri_y - 8'd5;
                end
            end
        end
    end

    // A escrita no tilemap so e habilitada no sub-modo de edicao de tile
    wire real_bg_wr_en = bg_upd & (bg_d[7] == 1'b0);

    // =========================================================
    // SINAIS DE INTERCONEXAO 
    // =========================================================
    wire [13:0] bg_rom_addr;
    wire [12:0] spr_rom_addr;
    wire [7:0]  bg_rom_data, spr_rom_data;
    wire [7:0]  bg_color;
    
    wire        spr_ativo_imediato;
    wire [7:0]  spr_color_imediato;
    wire        poly_ativo_imediato;
    wire [7:0]  poly_color_imediato;
     
    // =========================================================
    // MEMORIAS ROM INDEPENDENTES
    // =========================================================
    motor_tile u_rom_cenario_inst (
        .endereco         (bg_rom_addr),
        .clk              (clk25),
        .read             (1'b1),
        .dado_saida_tiles (bg_rom_data)
    );

    rom_sprites_inst u_rom_sprites_inst (
        .endereco           (spr_rom_addr),
        .clk                (clk25),
        .read               (1'b1),
        .dado_saida_sprites (spr_rom_data)
    );
     
    // =========================================================
    // 1. MOTOR DE BACKGROUND 
    // =========================================================
    motor_background u_bg (
        .clk        (clk25),
        .next_x     (next_x),
        .next_y     (next_y),
        .scroll_x   (bg_scroll_x),
        .scroll_y   (bg_scroll_y),
        .tm_wr_en   (real_bg_wr_en),
        .tm_wr_addr (bg_wr_addr),
        .tm_wr_data (bg_d),
        .rom_addr   (bg_rom_addr),
        .rom_data   (bg_rom_data),
        .cor_pixel  (bg_color)
    );
	 
    // =========================================================
    // 2. MOTOR DE SPRITES E CONTROLADOR
    // =========================================================
    wire        sprite_attr_wr_en;
    wire [4:0]  sprite_attr_wr_idx;
    wire [31:0] sprite_attr_wr_data;

    // O controlador de sprites so recebe comandos quando a MEF esta no
    // estado 11; nos demais estados spr_d fica em zero e o sprite selecionado
    // permanece parado
    controlador_sprite u_ctrl_sprite (
        .clk25        (clk25),
        .reset        (reset),
        .sw_up        (spr_d[3]),
        .sw_down      (spr_d[2]),
        .sw_left      (spr_d[1]),
        .sw_right     (spr_d[0]),
		  .modo_flip    (spr_d[7]),
		  .sw_change_char (spr_d[6]),
		  .id_alvo      (spr_d[5:4]),
        .attr_wr_en   (sprite_attr_wr_en),
        .attr_wr_idx  (sprite_attr_wr_idx),
        .attr_wr_data (sprite_attr_wr_data)
    );

    motor_sprites u_sprites (
        .clk          (clk25),
        .reset        (reset),
        .next_x       (next_x),
        .next_y       (next_y),
        .attr_wr_en   (sprite_attr_wr_en),
        .attr_wr_idx  (sprite_attr_wr_idx),
        .attr_wr_data (sprite_attr_wr_data),
        .rom_addr     (spr_rom_addr),
        .rom_data     (spr_rom_data),
        .sprite_ativo (spr_ativo_imediato),  
        .sprite_color (spr_color_imediato)
    );
     
    // =========================================================
    // 3. RASTERIZADORES DE POLIGONOS 
    // =========================================================
    wire ret_hit, tri_hit;
    wire [7:0] ret_c_out, tri_c_out;

    rasterizador_poligonos rast_retangulo (
        .clk(clk25), .jogo_x(next_x[9:1]), .jogo_y(next_y[9:1]), 
        .modo_ativo(2'd1),  
        .x0(ret_x), .y0(ret_y), .x1(ret_x + RET_W), .y1(ret_y + RET_H), .x2(9'd0), .y2(8'd0),
        .cor_indice(ret_cor), .poly_ativo(ret_hit), .poly_color(ret_c_out)
    );

    rasterizador_poligonos rast_triangulo (
        .clk(clk25), .jogo_x(next_x[9:1]), .jogo_y(next_y[9:1]), 
        .modo_ativo(2'd2),  
        .x0(tri_x), .y0(tri_y), 
        .x1(tri_x + TRI_BX), .y1(tri_y + TRI_HY), 
        .x2(tri_x - TRI_BX), .y2(tri_y + TRI_HY), 
        .cor_indice(tri_cor), .poly_ativo(tri_hit), .poly_color(tri_c_out)
    );

    wire ret_visivel = ret_hit & ret_en & (ret_cor != 8'd0);
    wire tri_visivel = tri_hit & tri_en & (tri_cor != 8'd0);

    // Triangulo tem prioridade sobre o retangulo quando os dois cobrem o mesmo pixel
    assign poly_ativo_imediato = ret_visivel | tri_visivel;
    assign poly_color_imediato = tri_visivel ? tri_c_out : (ret_visivel ? ret_c_out : 8'd0);

    // =========================================================
    // PIPELINE DE COMPENSACAO (alinha sprite e poligono com a latencia do fundo)
    // =========================================================
    reg        spr_ativo_atrasado;
    reg [7:0]  spr_color_atrasado;
    
    reg        poly_ativo_1, poly_ativo_2;
    reg [7:0]  poly_color_1, poly_color_2;

    always @(posedge clk25) begin
        spr_ativo_atrasado <= spr_ativo_imediato;
        spr_color_atrasado <= spr_color_imediato;
        
        poly_ativo_1       <= poly_ativo_imediato;
        poly_color_1       <= poly_color_imediato;
        poly_ativo_2       <= poly_ativo_1;
        poly_color_2       <= poly_color_1;
    end

    // =========================================================
    // COMPOSITOR FINAL E VGA
    // =========================================================
    wire [7:0] cor_final_indice;

    compositor meu_compositor (
        .bg_color     (bg_color),
        .sprite_ativo (spr_ativo_atrasado),
        .sprite_color (spr_color_atrasado),
        .poly_ativo   (poly_ativo_2),
        .poly_color   (poly_color_2),
        .cor_final    (cor_final_indice)
    );

    vga_driver u_vga (
        .clock    (clk25),
        .reset    (reset),
        .color_in (cor_final_indice),
        .next_x   (next_x),
        .next_y   (next_y),
        .hsync    (VGA_HS),
        .vsync    (VGA_VS),
        .red      (VGA_R),
        .green    (VGA_G),
        .blue     (VGA_B),
        .sync     (VGA_SYNC_N),
        .clk      (VGA_CLK),
        .blank    (VGA_BLANK_N)
    );

endmodule
