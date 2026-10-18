// ============================================================================
// unidade_quadro.v
// Unidade de Controle de Quadro: acompanha a varredura do VGA e informa
// ao resto do coprocessador em que momento do quadro estamos.
//
// Opera continuamente, independente das instrucoes (requisito do PBL).
//
// Entrada: 'v_ativo' = 1 enquanto o VGA esta desenhando as 480 linhas
//          visiveis (vem do vga_driver).
// Saidas:
//   vblank        = 1 fora da area visivel (intervalo vertical, ~1,4 ms)
//   inicio_vblank = pulso de 1 ciclo quando o quadro visivel termina.
//                   E o que libera a instrucao WAITV.
//   contador_quadros = quantos quadros ja foram exibidos (60 por segundo)
// ============================================================================
`timescale 1ns/1ps
module unidade_quadro (
    input  wire        clk,
    input  wire        reset,
    input  wire        v_ativo,

    output wire        vblank,
    output reg         inicio_vblank,
    output reg  [15:0] contador_quadros
);

    reg v_ativo_ant;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            v_ativo_ant      <= 1'b0;
            inicio_vblank    <= 1'b0;
            contador_quadros <= 16'd0;
        end else begin
            v_ativo_ant   <= v_ativo;
            // borda de descida de v_ativo = fim da ultima linha visivel
            inicio_vblank <= v_ativo_ant & ~v_ativo;
            if (v_ativo_ant & ~v_ativo)
                contador_quadros <= contador_quadros + 16'd1;
        end
    end

    assign vblank = ~v_ativo;

endmodule
