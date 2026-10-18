`timescale 1ns/1ps
// ============================================================================
// rasterizador_poligonos.v
// Testa se o pixel atual (jogo_x, jogo_y) esta dentro de um retangulo ou de
// um triangulo, e devolve o indice de cor correspondente.
//
// As coordenadas de entrada sao valores sem sinal de 9 bits. O teste do
// triangulo usa a funcao de aresta (edge function), que depende de
// subtracoes que podem dar resultado negativo. Por isso, antes de subtrair,
// cada coordenada e estendida para uma largura com bit de sinal de sobra
// (11 bits), garantindo que a subtracao e os produtos seguintes sejam
// calculados corretamente mesmo quando o resultado e negativo.
// ============================================================================
module rasterizador_poligonos (
    input wire clk,
    input wire [8:0] jogo_x,
    input wire [7:0] jogo_y,

    // Registradores de comando (parte do datapath)
    input wire [1:0] modo_ativo,   // 0 = nada, 1 = retangulo, 2 = triangulo
    input wire [8:0] x0, y0,       // retangulo: canto superior-esquerdo
    input wire [8:0] x1, y1,       // retangulo: canto inferior-direito | triangulo: vertice B
    input wire [8:0] x2, y2,       // triangulo: vertice C (nao usado no retangulo)
    input wire [7:0] cor_indice,   // cor do poligono (RGB332)

    output reg [7:0] poly_color,
    output reg       poly_ativo    // avisa ao compositor que este pixel pertence ao poligono
);

    // ---- Retangulo ----
    // Comparacao direta, sem subtracao com sinal; so precisa igualar as
    // larguras de jogo_y (8 bits) e y0/y1 (9 bits) para a sintese.
    wire [8:0] jogo_y9 = {1'b0, jogo_y};

    wire dentro_retangulo = (jogo_x  >= x0) && (jogo_x  < x1) &&
                            (jogo_y9 >= y0) && (jogo_y9 < y1);

    // ---- Triangulo: funcao de aresta (edge function) ----
    // Extensao das coordenadas para 11 bits com sinal (mantem o valor,
    // so reserva espaco para o sinal nas contas seguintes)
    wire signed [10:0] x0s = {2'b00, x0};
    wire signed [10:0] x1s = {2'b00, x1};
    wire signed [10:0] x2s = {2'b00, x2};
    wire signed [10:0] y0s = {2'b00, y0};
    wire signed [10:0] y1s = {2'b00, y1};
    wire signed [10:0] y2s = {2'b00, y2};
    wire signed [10:0] jxs = {2'b00, jogo_x};
    wire signed [10:0] jys = {3'b000, jogo_y};

    // Diferencas entre vertices e entre o pixel e cada vertice
    wire signed [11:0] dx01 = x1s - x0s;
    wire signed [11:0] dy01 = y1s - y0s;
    wire signed [11:0] dx12 = x2s - x1s;
    wire signed [11:0] dy12 = y2s - y1s;
    wire signed [11:0] dx20 = x0s - x2s;
    wire signed [11:0] dy20 = y0s - y2s;

    wire signed [11:0] pjx0 = jxs - x0s;
    wire signed [11:0] pjy0 = jys - y0s;
    wire signed [11:0] pjx1 = jxs - x1s;
    wire signed [11:0] pjy1 = jys - y1s;
    wire signed [11:0] pjx2 = jxs - x2s;
    wire signed [11:0] pjy2 = jys - y2s;

    // Produto cruzado de cada aresta com o vetor ate o pixel
    wire signed [23:0] e01 = (dx01 * pjy0) - (dy01 * pjx0);
    wire signed [23:0] e12 = (dx12 * pjy1) - (dy12 * pjx1);
    wire signed [23:0] e20 = (dx20 * pjy2) - (dy20 * pjx2);

    // Pixel esta dentro se estiver do mesmo lado das 3 arestas
    wire dentro_triangulo = (e01 >= 0 && e12 >= 0 && e20 >= 0) ||
                            (e01 <= 0 && e12 <= 0 && e20 <= 0);

    always @(*) begin
        poly_ativo = 1'b0;
        poly_color = 8'd0;
        case (modo_ativo)
            2'd1: if (dentro_retangulo) begin
                poly_ativo = 1'b1;
                poly_color = cor_indice;
            end
            2'd2: if (dentro_triangulo) begin
                poly_ativo = 1'b1;
                poly_color = cor_indice;
            end
            default: ; // modo 0: nenhum poligono ativo
        endcase
    end

endmodule
