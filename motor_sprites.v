module motor_sprites (
    input  wire        clk,
    input  wire        reset,

    // Varredura vinda do vga_driver (física 640x480)
    input  wire [9:0]  next_x,
    input  wire [9:0]  next_y,

    // Interface de escrita da tabela de atributos (32 sprites)
    input  wire        attr_wr_en,
    input  wire [4:0]  attr_wr_idx,
    input  wire [31:0] attr_wr_data,

    // Conexão com a ROM Externa (Dual-Port)
    output wire [13:0] rom_addr, 
    input  wire [7:0]  rom_data, 

    // Saída para o compositor
    output wire        sprite_ativo,
    output wire [7:0]  sprite_color
);

    // 1. Resolução lógica 320x240
    wire [8:0] logical_x = next_x[9:1];
    wire [7:0] logical_y = next_y[9:1];

    // 2. Banco de Atributos dos 32 Sprites
    reg [31:0] sprite_ram [0:31];
    integer k;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // Zera todos os sprites
            for (k = 0; k < 32; k = k + 1)
                sprite_ram[k] <= 32'd0;
                
            // --- TESTE: Ligar o Sprite 0 ---
            // Bit 27: Enable = 1
            // Bits 24:17: Tile Base = 3 (Smiley Face)
            // Bits 16:9: Posição Y = 100
            // Bits 8:0: Posição X = 100
            sprite_ram[0] <= {4'b0000, 1'b1, 2'b00, 8'd3, 8'd100, 9'd100};

        end else if (attr_wr_en) begin
            sprite_ram[attr_wr_idx] <= attr_wr_data;
        end
    end

    // 3. Teste de Cobertura e Resolução de Prioridade (Maior ID vence)
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

    reg [4:0] winner_idx;
    reg       winner_hit;

    integer j;
    always @(*) begin
        winner_hit = 1'b0;
        winner_idx = 5'd0;
        for (j = 0; j < 32; j = j + 1) begin
            if (hit_mask[j]) begin
                winner_hit = 1'b1;
                winner_idx = j[4:0];
            end
        end
    end

    // 4. Decodificação do Sprite Selecionado e Flip
    wire [31:0] sel_attr   = sprite_ram[winner_idx];
    wire [7:0]  base_tile  = sel_attr[24:17];
    wire        flip_x     = sel_attr[25];
    wire        flip_y     = sel_attr[26];

    wire [3:0] raw_dx = dx_arr[winner_idx][3:0];
    wire [3:0] raw_dy = dy_arr[winner_idx][3:0];

    wire [3:0] local_x = flip_x ? (4'd15 - raw_dx) : raw_dx;
    wire [3:0] local_y = flip_y ? (4'd15 - raw_dy) : raw_dy;

    // Seleciona o quadrante (0..3) somando ao base_tile
    wire [1:0] sub_tile_quad = {local_y[3], local_x[3]};
    wire [7:0] active_tile   = base_tile + {6'd0, sub_tile_quad};

    // Manda o endereço para a Porta B da ROM lá no top_video
    assign rom_addr = {active_tile, local_y[2:0], local_x[2:0]};

    // Atraso de 1 ciclo do hit_reg para acompanhar a leitura da ROM
    reg hit_reg;
    always @(posedge clk or posedge reset) begin
        if (reset) hit_reg <= 1'b0;
        else       hit_reg <= winner_hit;
    end

    // 5. Recebe o dado da ROM (transparente se for índice 0)
    assign sprite_color = rom_data;
    assign sprite_ativo = hit_reg && (rom_data != 8'd0);

endmodule