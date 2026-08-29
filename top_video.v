// ============================================================================
// top_video.v
// Integra Fundo (com escrita pontual), Sprites e Poligonos.
// ============================================================================
module top_video (
    input  wire        CLOCK_50,    
    input  wire        reset,       
    
    input  wire        btn_write,   // <-- Sinal do botão vindo do DE1_SOC_golden_top
	 input  wire [9:0]  SW_in,       // <-- Alterado para receber as 10 chaves

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
reg key1_r1, key1_r2;
    always @(posedge clk25) begin
        key1_r1 <= ~btn_write;      
        key1_r2 <= key1_r1;
    end
    wire key1_press = (key1_r1 & ~key1_r2); 

    reg [1:0] poly_modo;
    reg [8:0] poly_x0, poly_x1, poly_x2;
    reg [7:0] poly_y0, poly_y1, poly_y2;
    reg [7:0] poly_cor;

    // Largura e altura fixas para teste de translação do retângulo (ex: 150x100 pixels)
    parameter [8:0] RET_LARGURA = 9'd150;
    parameter [7:0] RET_ALTURA  = 8'd100;

    always @(posedge clk25 or posedge reset) begin
        if (reset) begin
            poly_modo <= 2'd1;     // 1 = Retângulo
            poly_x0   <= 9'd50;    poly_y0   <= 8'd50;
            // X1 e Y1 são calculados automaticamente com base na largura/altura
            poly_x1   <= 9'd50 + RET_LARGURA;   
            poly_y1   <= 8'd50 + RET_ALTURA;
            poly_x2   <= 9'd0;     poly_y2   <= 8'd0;
            poly_cor  <= 8'd5;
        end else if (key1_press) begin
            case (SW_in[9:7])
                3'b000: begin // Comando 0: Move a âncora X (X0), arrastando X1 junto para manter o tamanho
                    poly_x0 <= {1'b0, SW_in[7:0]};
                    poly_x1 <= {1'b0, SW_in[7:0]} + RET_LARGURA;
                end
                3'b001: begin // Comando 1: Move a âncora Y (Y0), arrastando Y1 junto
                    poly_y0 <= SW_in[7:0];
                    poly_y1 <= SW_in[7:0] + RET_ALTURA;
                end
                3'b100: poly_modo <= SW_in[1:0];         // Comando 4: Muda Modo
                3'b101: poly_cor  <= SW_in[7:0];         // Comando 5: Muda Cor
                default: ;
            endcase
        end
    end

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