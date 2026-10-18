// ============================================================================
// compositor.v
// Decide, pixel a pixel, qual camada vai para a tela.
//
// Prioridade (da mais alta para a mais baixa):
//   1. sprite da FRENTE   (atributo BACK = 0)
//   2. poligono
//   3. sprite de TRAS     (atributo BACK = 1)
//   4. background (sempre opaco)
// Indice de cor 0 e transparente em sprites e poligonos (os sinais *_ativo
// ja chegam em 0 quando o pixel e transparente).
// ============================================================================
`timescale 1ns/1ps
module compositor (
    input  wire [7:0] bg_color,

    input  wire       poly_ativo,
    input  wire [7:0] poly_color,

    input  wire       sprite_ativo,
    input  wire [7:0] sprite_color,
    input  wire       sprite_back,

    output reg  [7:0] cor_final
);
    always @(*) begin
        if (sprite_ativo && !sprite_back)
            cor_final = sprite_color;          // 1. sprite da frente
        else if (poly_ativo)
            cor_final = poly_color;            // 2. poligono
        else if (sprite_ativo)
            cor_final = sprite_color;          // 3. sprite de tras
        else
            cor_final = bg_color;              // 4. fundo
    end
endmodule
