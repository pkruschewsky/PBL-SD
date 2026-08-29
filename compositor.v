// Módulo: Compositor de Prioridades
// Decide, pixel a pixel, qual camada "vence" e vai pra tela.
// Prioridade (da mais alta pra mais baixa): Sprite > Poligono > Background
module compositor (
    input wire [7:0] bg_color,       // sempre tem uma cor valida (camada base)

    input wire        poly_ativo,
    input wire [7:0]  poly_color,

    input wire        sprite_ativo,
    input wire [7:0]  sprite_color,

    output reg [7:0] cor_final       // indice de cor final (vai pra paleta)
);

    always @(*) begin
        if (sprite_ativo && sprite_color != 8'd0) begin
            cor_final = sprite_color;   // Prioridade 1
        end else if (poly_ativo && poly_color != 8'd0) begin
            cor_final = poly_color;     // Prioridade 2
        end else begin
            cor_final = bg_color;       // Prioridade 3 (base)
        end
    end

endmodule
