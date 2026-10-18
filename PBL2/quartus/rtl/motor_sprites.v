// ============================================================================
// motor_sprites.v
// Banco de atributos de 32 sprites e logica de varredura/prioridade.
//
//   - Escrita por campo, vinda do nucleo:
//       pos_we  -> grava so x e y          (SPR_POS, SPR_MOVE)
//       attr_we -> grava so tile/flags     (SPR_ATTR)
//     Assim um SPR_POS nao apaga o tile, e um SPR_ATTR nao move o sprite.
//   - Porta de leitura da posicao (rd_idx -> rd_x, rd_y): o SPR_MOVE usa a
//     posicao atual para somar o deslocamento na ULA.
//   - Atributo BACK (bit 28): 1 = sprite fica atras dos poligonos. O motor
//     informa o BACK do sprite vencedor ao compositor.
//   - Reset: todos os sprites desligados.
//   - A ROM tem 2 ciclos de latencia, entao 'hit' e 'back' tambem sao
//     atrasados 2 ciclos para chegar junto com o dado da ROM.
//
// Formato de cada entrada (32 bits):
//   [8:0] x   [16:9] y   [24:17] tile   [25] flip_x   [26] flip_y
//   [27] enable   [28] back   [31:29] livre
// Prioridade entre sprites: menor indice vence (sprite 0 na frente).
// ============================================================================
`timescale 1ns/1ps
module motor_sprites (
    input  wire        clk,
    input  wire        reset,
    // Varredura vinda do vga_driver (fisica 640x480)
    input  wire [9:0]  next_x,
    input  wire [9:0]  next_y,
    // Escrita por campo (vinda do nucleo)
    input  wire        pos_we,
    input  wire        attr_we,
    input  wire [4:0]  wr_idx,
    input  wire [8:0]  wr_x,
    input  wire [7:0]  wr_y,
    input  wire [11:0] wr_attr,      // {back, flip_y, flip_x, enable, tile[7:0]}
    // Leitura da posicao (para o SPR_MOVE)
    input  wire [4:0]  rd_idx,
    output wire [8:0]  rd_x,
    output wire [7:0]  rd_y,
    // Conexao com a ROM de sprites (8192 x 8, latencia de 2 ciclos)
    output wire [12:0] rom_addr,
    input  wire [7:0]  rom_data,
    // Saida para o compositor (2 ciclos depois de next_x/next_y)
    output wire        sprite_ativo,
    output wire [7:0]  sprite_color,
    output wire        sprite_back
);
    wire [8:0] logical_x = next_x[9:1];
    wire [7:0] logical_y = next_y[9:1];

    // ------------------------------------------------------------------
    // Banco de atributos
    // ------------------------------------------------------------------
    reg [31:0] sprite_ram [0:31];
    integer k;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (k = 0; k < 32; k = k + 1)
                sprite_ram[k] <= 32'd0;              // todos desligados
        end else begin
            if (pos_we) begin
                sprite_ram[wr_idx][8:0]  <= wr_x;
                sprite_ram[wr_idx][16:9] <= wr_y;
            end
            if (attr_we) begin
                sprite_ram[wr_idx][24:17] <= wr_attr[7:0];   // tile
                sprite_ram[wr_idx][27]    <= wr_attr[8];     // enable
                sprite_ram[wr_idx][25]    <= wr_attr[9];     // flip_x
                sprite_ram[wr_idx][26]    <= wr_attr[10];    // flip_y
                sprite_ram[wr_idx][28]    <= wr_attr[11];    // back
            end
        end
    end

    assign rd_x = sprite_ram[rd_idx][8:0];
    assign rd_y = sprite_ram[rd_idx][16:9];

    // ------------------------------------------------------------------
    // Teste de cobertura: um bit por sprite
    // ------------------------------------------------------------------
    wire [31:0] hit_mask;
    wire [4:0]  dx_arr [0:31];
    wire [4:0]  dy_arr [0:31];
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gen_hit
            wire [8:0] spr_x      = sprite_ram[i][8:0];
            wire [7:0] spr_y      = sprite_ram[i][16:9];
            wire       spr_enable = sprite_ram[i][27];
            wire [8:0] diff_x = logical_x - spr_x;
            wire [7:0] diff_y = logical_y - spr_y;
            assign hit_mask[i] = spr_enable && (diff_x < 9'd16) && (diff_y < 8'd16);
            assign dx_arr[i]   = diff_x[4:0];
            assign dy_arr[i]   = diff_y[4:0];
        end
    endgenerate

    // Prioridade: menor indice vence
    reg [4:0] winner_idx;
    reg       winner_hit;
    integer j;
    always @(*) begin
        winner_hit = 1'b0;
        winner_idx = 5'd0;
        for (j = 31; j >= 0; j = j - 1) begin
            if (hit_mask[j]) begin
                winner_hit = 1'b1;
                winner_idx = j[4:0];
            end
        end
    end

    // Espelhamento e quadrante (cada sprite = 4 tiles de 8x8)
    wire [31:0] sel_attr  = sprite_ram[winner_idx];
    wire [7:0]  base_tile = sel_attr[24:17];
    wire        flip_x    = sel_attr[25];
    wire        flip_y    = sel_attr[26];
    wire        back      = sel_attr[28];

    wire [3:0] raw_dx  = dx_arr[winner_idx][3:0];
    wire [3:0] raw_dy  = dy_arr[winner_idx][3:0];
    wire [3:0] local_x = flip_x ? (4'd15 - raw_dx) : raw_dx;
    wire [3:0] local_y = flip_y ? (4'd15 - raw_dy) : raw_dy;

    wire [1:0] sub_tile_quad = {local_y[3], local_x[3]};
    wire [7:0] active_tile   = base_tile + {6'd0, sub_tile_quad};

    wire [7:0] safe_tile = winner_hit ? active_tile : 8'd0;
    wire [3:0] safe_x    = winner_hit ? local_x     : 4'd0;
    wire [3:0] safe_y    = winner_hit ? local_y     : 4'd0;

    assign rom_addr = {safe_tile[6:0], safe_y[2:0], safe_x[2:0]};

    // ------------------------------------------------------------------
    // Atraso de 2 ciclos: alinha hit/back com o dado da ROM
    // ------------------------------------------------------------------
    reg hit_r1, hit_r2, back_r1, back_r2;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            hit_r1 <= 1'b0; hit_r2 <= 1'b0; back_r1 <= 1'b0; back_r2 <= 1'b0;
        end else begin
            hit_r1  <= winner_hit;  hit_r2  <= hit_r1;
            back_r1 <= back;        back_r2 <= back_r1;
        end
    end

    assign sprite_color = rom_data;
    assign sprite_ativo = hit_r2 && (rom_data != 8'd0);   // indice 0 = transparente
    assign sprite_back  = back_r2;

endmodule
