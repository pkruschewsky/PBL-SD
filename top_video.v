// ============================================================================
// top_video.v
// Integra Fundo (com escrita pontual), Sprites e Poligonos.
// ============================================================================
module top_video (
    input  wire        CLOCK_50,    
    input  wire        reset,       
	 
    input  wire        btn_write,    // <-- KEY[1]
    input  wire        KEY_move_dir, // <-- KEY[2]
    input  wire        KEY_move_esq, // <-- KEY[3]
    input  wire [9:0]  SW_in,       

    input  wire [8:0]  SW_scroll_x, 
    input  wire [7:0]  SW_scroll_y,
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
/*
    // =========================================================
    // LÓGICA DO BOTÃO E ESCRITA (Requisito 4.3)
    // =========================================================
    reg key1_r1, key1_r2;
    always @(posedge clk25) begin
        key1_r1 <= ~btn_write;      
        key1_r2 <= key1_r1;
    end
    wire key1_press = (key1_r1 & ~key1_r2); 

    reg        teste_wr_en;
    reg [10:0] teste_wr_addr;
    reg [7:0]  teste_wr_data;

    always @(posedge clk25 or posedge reset) begin
        if (reset) begin
            teste_wr_en   <= 1'b0;
            teste_wr_addr <= 11'd0;
            teste_wr_data <= 8'd0;
        end else begin
            if (key1_press) begin
                teste_wr_en   <= 1'b1;         
                teste_wr_addr <= 11'd2; // Endereço de teste no meio da tela     
                teste_wr_data <= SW_tile_sel;  
            end else begin
                teste_wr_en   <= 1'b0;         
            end
        end
    end
	 
*/	 
	 // =========================================================
    // LÓGICA DO BOTÃO E REGISTRADORES DO POLÍGONO Requisito 4.5
    // =========================================================
// =========================================================
    // LÓGICA DE TESTE INDIVIDUAL MULTIPLEXADO (Rasterizadores)
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

    // Registradores Independentes (Visibilidade, Posição âncora, Cor)
    reg ret_en, tri_en;
    reg [8:0] ret_x, tri_x;
    reg [7:0] ret_y, tri_y;
    reg [7:0] ret_cor, tri_cor;

    // Tamanhos fixos para evitar distorção
    parameter [8:0] RET_W = 9'd80;   parameter [7:0] RET_H = 8'd40;
    parameter [8:0] TRI_BX = 9'd40;  parameter [7:0] TRI_HY = 8'd60; // 40 pra cada lado, 60 de altura

    always @(posedge clk25 or posedge reset) begin
        if (reset) begin
            ret_en <= 1'b1;  ret_x <= 9'd50;  ret_y <= 8'd50;  ret_cor <= 8'd5;
            tri_en <= 1'b1;  tri_x <= 9'd200; tri_y <= 8'd100; tri_cor <= 8'd15;
        end else begin
            // Aplica Cor e Visibilidade (KEY[1])
            if (key1_press) begin
                if (SW_in[9] == 1'b0) begin ret_cor <= {1'b0, SW_in[6:0]}; ret_en <= SW_in[7]; end
                else                  begin tri_cor <= {1'b0, SW_in[6:0]}; tri_en <= SW_in[7]; end
            end
            
            // Movimentação +5 (KEY[2])
            else if (key2_press) begin
                if (SW_in[9] == 1'b0) begin
                    if (SW_in[8] == 1'b0) ret_x <= ret_x + 9'd5; else ret_y <= ret_y + 8'd5;
                end else begin
                    if (SW_in[8] == 1'b0) tri_x <= tri_x + 9'd5; else tri_y <= tri_y + 8'd5;
                end
            end
            
            // Movimentação -5 (KEY[3])
            else if (key3_press) begin
                if (SW_in[9] == 1'b0) begin
                    if (SW_in[8] == 1'b0) ret_x <= ret_x - 9'd5; else ret_y <= ret_y - 8'd5;
                end else begin
                    if (SW_in[8] == 1'b0) tri_x <= tri_x - 9'd5; else tri_y <= tri_y - 8'd5;
                end
            end
        end
    end

    // =========================================================
    // INSTANCIAÇÃO DE MÚLTIPLOS RASTERIZADORES
    // =========================================================
    wire ret_hit, tri_hit;
    wire [7:0] ret_c_out, tri_c_out;

    // 1. Retângulo 
    rasterizador_poligonos rast_retangulo (
        .clk(clk25), .jogo_x(next_x[9:1]), .jogo_y(next_y[9:1]), 
        .modo_ativo(2'd1),  
        .x0(ret_x), .y0(ret_y), .x1(ret_x + RET_W), .y1(ret_y + RET_H), .x2(9'd0), .y2(8'd0),
        .cor_indice(ret_cor), .poly_ativo(ret_hit), .poly_color(ret_c_out)
    );

    // 2. Triângulo (Cálculo automático dos 3 vértices a partir do centro/topo)
    rasterizador_poligonos rast_triangulo (
        .clk(clk25), .jogo_x(next_x[9:1]), .jogo_y(next_y[9:1]), 
        .modo_ativo(2'd2),  
        .x0(tri_x), .y0(tri_y), 
        .x1(tri_x + TRI_BX), .y1(tri_y + TRI_HY), // Base direita
        .x2(tri_x - TRI_BX), .y2(tri_y + TRI_HY), // Base esquerda
        .cor_indice(tri_cor), .poly_ativo(tri_hit), .poly_color(tri_c_out)
    );

    // Unifica os dois sinais antes de mandar para o pipeline de atraso
    assign poly_ativo_imediato = (ret_hit & ret_en) | (tri_hit & tri_en);
    // Prioridade visual: Triângulo fica por cima do Retângulo se colidirem
    assign poly_color_imediato = (tri_hit & tri_en) ? tri_c_out : (ret_hit & ret_en ? ret_c_out : 8'd0);

    // =========================================================
    // SINAIS DE INTERCONEXÃO 
    // =========================================================
    wire [13:0] bg_rom_addr, spr_rom_addr;
    wire [7:0]  bg_rom_data, spr_rom_data;
    wire [7:0]  bg_color;
    
    wire        spr_ativo_imediato;
    wire [7:0]  spr_color_imediato;
    wire        poly_ativo_imediato;
    wire [7:0]  poly_color_imediato;

    // =========================================================
    // ROM COMPARTILHADA (Dual-Port)
    // =========================================================
    rom_tiles u_rom_compartilhada (
        .clock     (clk25),
        .address_a (bg_rom_addr),   
        .q_a       (bg_rom_data),
        .address_b (spr_rom_addr),  
        .q_b       (spr_rom_data)
    );

    // =========================================================
    // 1. MOTOR DE BACKGROUND 
    // =========================================================
    motor_background u_bg (
        .clk        (clk25),
        .next_x     (next_x),
        .next_y     (next_y),
        .scroll_x   (SW_scroll_x),
        .scroll_y   (SW_scroll_y),
        
		  .tm_wr_en   (1'b0),          // <-- Escrita no fundo desligada
        .tm_wr_addr (11'd0),
        .tm_wr_data (8'd0),
        
        .rom_addr   (bg_rom_addr),
        .rom_data   (bg_rom_data),
        .cor_pixel  (bg_color)
    );

    // =========================================================
    // 2. MOTOR DE SPRITES 
    // =========================================================
    motor_sprites u_sprites (
        .clk          (clk25),
        .reset        (reset),
        .next_x       (next_x),
        .next_y       (next_y),
        .attr_wr_en   (1'b0), 
        .attr_wr_idx  (5'd0),
        .attr_wr_data (32'd0),
        .rom_addr     (spr_rom_addr),
        .rom_data     (spr_rom_data),
        .sprite_ativo (spr_ativo_imediato), 
        .sprite_color (spr_color_imediato)
    );

    // =========================================================
    // 3. RASTERIZADOR DE POLÍGONOS 
    // =========================================================
	 rasterizador_poligonos meu_rasterizador (
        .clk        (clk25),
        .jogo_x     (next_x[9:1]), 
        .jogo_y     (next_y[9:1]), 
        .modo_ativo (poly_modo),      
        .x0(poly_x0),  .y0(poly_y0),  // <-- Fios conectados!
        .x1(poly_x1),  .y1(poly_y1),  // <-- Fios conectados!
        .x2(poly_x2),  .y2(poly_y2),  // <-- Fios conectados!
        .cor_indice (poly_cor),
        .poly_ativo (poly_ativo_imediato),
        .poly_color (poly_color_imediato)
    );
    // =========================================================
    // PIPELINE DE COMPENSAÇÃO (Sincronização)
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