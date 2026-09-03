// Módulo: Rasterizador de Polígonos
// Testa se o pixel atual (jogo_x, jogo_y) está dentro de um retângulo ou triângulo.
//
// CORRECAO (apontada via revisao com Gemini): as coordenadas de entrada tem
// 9 bits sem sinal. Subtrair direto (ex: x1-x0) mantinha o resultado preso
// em 9 bits, e diferencas maiores que 255 estouravam o bit de sinal quando
// convertidas com $signed() - o numero virava negativo por engano, o que
// destruia o preenchimento do triangulo.
// A correcao: estender toda coordenada para 11 bits ANTES de subtrair,
// garantindo bits de sobra pro sinal.
module rasterizador_poligonos (
    input wire clk,
    input wire [8:0] jogo_x,
    input wire [7:0] jogo_y,

    // Vindos de registradores carregados por comando (parte do datapath)
    input wire [1:0] modo_ativo,   // 0 = nada, 1 = retangulo, 2 = triangulo
    input wire [8:0] x0, y0,       // retangulo: canto superior-esquerdo
    input wire [8:0] x1, y1,       // retangulo: canto inferior-direito | triangulo: vertice B
    input wire [8:0] x2, y2,       // triangulo: vertice C (nao usado no retangulo)
    input wire [7:0] cor_indice,   // indice de cor da paleta

    output reg [7:0] poly_color,
    output reg       poly_ativo    // avisa ao compositor: "este pixel e meu"
);

    // ---- Retangulo ----
    // Aqui nao ha subtracao com sinal, so comparacao direta (>=, <),
    // entao nao sofre do mesmo problema - so precisa igualar as larguras
    // pra comparacao nao dar erro de sintese (jogo_y tem 8 bits, y0/y1 tem 9).
    wire [8:0] jogo_y9 = {1'b0, jogo_y};

    wire dentro_retangulo = (jogo_x  >= x0) && (jogo_x  < x1) &&
                            (jogo_y9 >= y0) && (jogo_y9 < y1);

    // ---- Triangulo: funcao de aresta (edge function) ----
    // 1. Estende cada coordenada (9 ou 8 bits, sem sinal) para 11 bits com
    //    sinal, preenchendo com zeros a esquerda. Isso NAO muda o valor,
    //    so garante espaco de sobra pro sinal nas contas seguintes.
    wire signed [10:0] x0s = {2'b00, x0};
    wire signed [10:0] x1s = {2'b00, x1};
    wire signed [10:0] x2s = {2'b00, x2};
    wire signed [10:0] y0s = {2'b00, y0};
    wire signed [10:0] y1s = {2'b00, y1};
    wire signed [10:0] y2s = {2'b00, y2};
    wire signed [10:0] jxs = {2'b00, jogo_x};
    wire signed [10:0] jys = {3'b000, jogo_y};

    // 2. Diferencas - agora corretas, com sinal preservado (12 bits de
    //    largura pra ter folga: o maior valor possivel, 511, cabe tranquilo).
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

    // 3. Produtos (12 bits x 12 bits = ate 24 bits de resultado - largura
    //    generosa de proposito, pra nunca faltar espaco).
    wire signed [23:0] e01 = (dx01 * pjy0) - (dy01 * pjx0);
    wire signed [23:0] e12 = (dx12 * pjy1) - (dy12 * pjx1);
    wire signed [23:0] e20 = (dx20 * pjy2) - (dy20 * pjx2);

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
            default: ; // modo 0 = nada ativo
        endcase
    end

endmodule
