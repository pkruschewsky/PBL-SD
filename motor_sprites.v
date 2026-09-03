// ============================================================================
// motor_sprites.v
// Banco de atributos de 32 sprites e logica de varredura/prioridade.
// Para cada pixel logico, verifica quais sprites cobrem aquela posicao e
// escolhe o de menor indice entre os que colidem (prioridade fixa por ID).
// Decodifica o quadrante do sprite vencedor e monta o endereco de leitura
// da ROM de sprites, aplicando espelhamento horizontal/vertical.
// ============================================================================
module motor_sprites (
    input  wire        clk,
    input  wire        reset,
    // Varredura vinda do vga_driver (fisica 640x480)
    input  wire [9:0]  next_x,
    input  wire [9:0]  next_y,
    // Interface de escrita da tabela de atributos (32 sprites)
    input  wire        attr_wr_en,
    input  wire [4:0]  attr_wr_idx,
    input  wire [31:0] attr_wr_data,
    // Conexao com a ROM dedicada de sprites (1 porta, 8192 palavras -> 13 bits)
    output wire [12:0] rom_addr, 
    input  wire [7:0]  rom_data, 
    // Saida para o compositor
    output wire        sprite_ativo,
    output wire [7:0]  sprite_color
);
    // Resolucao logica 320x240
    wire [8:0] logical_x = next_x[9:1];
    wire [7:0] logical_y = next_y[9:1];

    // Banco de atributos dos 32 sprites
    reg [31:0] sprite_ram [0:31];
    integer k;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // Zera todos os sprites
            for (k = 0; k < 32; k = k + 1)
                sprite_ram[k] <= 32'd0;

            // Sprite 0: personagem controlado pelo jogador
            sprite_ram[0] <= {4'b0000, 1'b1, 2'b00, 8'd0, 8'd100, 9'd100};

            // Sprites 1 a 3: inimigos parados, posicoes fixas de demonstracao
            sprite_ram[1] <= {4'b0000, 1'b1, 2'b00, 8'd4, 8'd50, 9'd200};
            sprite_ram[2] <= {4'b0000, 1'b1, 2'b00, 8'd8, 8'd150, 9'd50};
            sprite_ram[3] <= {4'b0000, 1'b1, 2'b00, 8'd16, 8'd180, 9'd250};

        end else if (attr_wr_en) begin
            sprite_ram[attr_wr_idx] <= attr_wr_data;
        end
    end

    // Teste de cobertura: um bit por sprite, indicando se ele cobre o pixel atual
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

    // Resolucao de prioridade: menor indice vence entre os sprites que colidem
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

    // Decodificacao do sprite vencedor e aplicacao de espelhamento
    wire [31:0] sel_attr   = sprite_ram[winner_idx];
    wire [7:0]  base_tile  = sel_attr[24:17];
    wire        flip_x     = sel_attr[25];
    wire        flip_y     = sel_attr[26];

    wire [3:0] raw_dx = dx_arr[winner_idx][3:0];
    wire [3:0] raw_dy = dy_arr[winner_idx][3:0];
    wire [3:0] local_x = flip_x ? (4'd15 - raw_dx) : raw_dx;
    wire [3:0] local_y = flip_y ? (4'd15 - raw_dy) : raw_dy;

    wire [1:0] sub_tile_quad = {local_y[3], local_x[3]};
    wire [7:0] active_tile   = base_tile + {6'd0, sub_tile_quad};

    // Sem nenhum sprite cobrindo o pixel, o endereco fica travado no tile 0
    // (indice transparente), em vez de repetir a ultima posicao valida
    wire [7:0] safe_tile = winner_hit ? active_tile : 8'd0;
    wire [3:0] safe_x    = winner_hit ? local_x     : 4'd0;
    wire [3:0] safe_y    = winner_hit ? local_y     : 4'd0;

    // Endereco de 13 bits para a rom_sprites
    assign rom_addr = {safe_tile[6:0], safe_y[2:0], safe_x[2:0]};

    // Atraso de 1 ciclo para alinhar o sinal de cobertura com a latencia de leitura da ROM
    reg hit_reg;
    always @(posedge clk or posedge reset) begin
        if (reset) hit_reg <= 1'b0;
        else       hit_reg <= winner_hit;
    end

    // Dado da ROM: indice de cor 0 e transparente
    assign sprite_color = rom_data;
    assign sprite_ativo = hit_reg && (rom_data != 8'd0);

endmodule
