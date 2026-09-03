// ============================================================================
// controlador_sprite.v
// Controla 4 sprites simultaneos (id_alvo 0-3), cada um com posicao propria,
// personagem atual e espelhamento horizontal/vertical.
//
// O sprite selecionado por id_alvo responde as chaves de direcao: em modo
// normal elas movem o sprite; em modo_flip elas espelham a imagem no eixo
// correspondente. sw_change_char percorre os 7 personagens disponiveis
// (indices 0 a 6) a cada borda de subida.
// ============================================================================
module controlador_sprite (
    input  wire        clk25,
    input  wire        reset,
    input  wire        sw_up,
    input  wire        sw_down,
    input  wire        sw_left,
    input  wire        sw_right,
    input  wire        modo_flip,      // SW[7]: direcoes espelham em vez de mover
    input  wire        sw_change_char, // SW[6]: avanca o personagem do sprite selecionado
    input  wire [1:0]  id_alvo,        // SW[5:4]: sprite selecionado (0 a 3)
    output reg         attr_wr_en,
    output reg  [4:0]  attr_wr_idx,
    output reg  [31:0] attr_wr_data
);

    localparam       ENABLE = 1'b1;
    localparam [8:0] X_MIN = 9'd0,   X_MAX = 9'd304;
    localparam [7:0] Y_MIN = 8'd0,   Y_MAX = 8'd224;

    // Estado de cada um dos 4 sprites controlaveis
    reg [8:0] pos_x [0:3];
    reg [7:0] pos_y [0:3];
    reg [2:0] char_idx [0:3];   // personagem atual (0 a 6) de cada sprite
    reg       flip_x_reg [0:3];
    reg       flip_y_reg [0:3];

    // ---------------------------------------------------------
    // Detector de borda de subida em sw_change_char
    // ---------------------------------------------------------
    reg sw6_r1, sw6_r2;
    always @(posedge clk25) begin
        sw6_r1 <= sw_change_char;
        sw6_r2 <= sw6_r1;
    end
    wire sw6_press = (sw6_r1 & ~sw6_r2);

    // Timer que fixa a cadencia de movimento/flip em ~20 Hz (clk25 = 25 MHz)
    localparam [20:0] SPEED_LIMIT = 21'd1_250_000;
    reg [20:0] speed_cnt;
    wire tick = (speed_cnt == SPEED_LIMIT);

    always @(posedge clk25 or posedge reset) begin
        if (reset)      speed_cnt <= 21'd0;
        else if (tick)  speed_cnt <= 21'd0;
        else            speed_cnt <= speed_cnt + 21'd1;
    end

    integer i;

    always @(posedge clk25 or posedge reset) begin
        if (reset) begin
            // Posicoes e personagens iniciais dos 4 sprites
            pos_x[0] <= 9'd100; pos_y[0] <= 8'd100; char_idx[0] <= 3'd0;
            pos_x[1] <= 9'd200; pos_y[1] <= 8'd50;  char_idx[1] <= 3'd1;
            pos_x[2] <= 9'd50;  pos_y[2] <= 8'd150; char_idx[2] <= 3'd2;
            pos_x[3] <= 9'd250; pos_y[3] <= 8'd180; char_idx[3] <= 3'd4;

            for (i = 0; i < 4; i = i + 1) begin
                flip_x_reg[i] <= 1'b0;
                flip_y_reg[i] <= 1'b0;
            end

            attr_wr_en  <= 1'b0;
            attr_wr_idx <= 5'd0;
        end else begin
            attr_wr_en <= 1'b0;

            // Troca de personagem tem prioridade e acontece na hora,
            // sem esperar o tick de movimento
            if (sw6_press) begin
                if (char_idx[id_alvo] >= 3'd6)
                    char_idx[id_alvo] <= 3'd0;
                else
                    char_idx[id_alvo] <= char_idx[id_alvo] + 3'd1;

                attr_wr_idx <= {3'b000, id_alvo};
                attr_wr_en  <= 1'b1;
            end
            // Movimento ou flip do sprite selecionado, a cada tick
            else if (tick) begin
                if (modo_flip) begin
                    if (sw_left)       flip_x_reg[id_alvo] <= 1'b1;
                    else if (sw_right) flip_x_reg[id_alvo] <= 1'b0;

                    if (sw_up)         flip_y_reg[id_alvo] <= 1'b1;
                    else if (sw_down)  flip_y_reg[id_alvo] <= 1'b0;
                end
                else begin
                    if (sw_up    && pos_y[id_alvo] > Y_MIN) pos_y[id_alvo] <= pos_y[id_alvo] - 8'd1;
                    if (sw_down  && pos_y[id_alvo] < Y_MAX) pos_y[id_alvo] <= pos_y[id_alvo] + 8'd1;
                    if (sw_left  && pos_x[id_alvo] > X_MIN) pos_x[id_alvo] <= pos_x[id_alvo] - 9'd1;
                    if (sw_right && pos_x[id_alvo] < X_MAX) pos_x[id_alvo] <= pos_x[id_alvo] + 9'd1;
                end

                attr_wr_idx <= {3'b000, id_alvo};
                attr_wr_en  <= 1'b1;
            end
        end
    end

    // tile_base = indice do personagem * 4 (cada personagem ocupa 4 tiles
    // consecutivos no sprites_rom.mif)
    wire [7:0] current_tile = {3'b000, char_idx[id_alvo], 2'b00};

    always @(*) begin
        attr_wr_data = {4'b0000, ENABLE, flip_y_reg[id_alvo], flip_x_reg[id_alvo], current_tile, pos_y[id_alvo], pos_x[id_alvo]};
    end

endmodule
