// ============================================================================
// ula.v
// Unidade Logica e Aritmetica de 16 bits do coprocessador.
//
//   op = 00 : ADD   resultado = a + b
//   op = 01 : SUB   resultado = a - b
//   op = 10 : AND   resultado = a & b
//   op = 11 : OR    resultado = a | b
//
// Flags (combinacionais; quem decide se elas sao guardadas e a UC):
//   N : bit 15 do resultado (negativo em complemento de 2)
//   Z : resultado == 0
//   C : ADD -> vai-um para fora do bit 15
//       SUB -> "nao-emprestimo" (1 quando a >= b sem sinal), como no ARM
//       AND/OR -> 0
//   V : overflow em complemento de 2 (so ADD/SUB; 0 em AND/OR)
//       ADD: a e b com o mesmo sinal e resultado com sinal diferente
//       SUB: a e b com sinais diferentes e resultado com sinal diferente de a
// ============================================================================
`timescale 1ns/1ps
module ula (
    input  wire [15:0] a,
    input  wire [15:0] b,
    input  wire [1:0]  op,
    output reg  [15:0] resultado,
    output wire [3:0]  flags          // {N, Z, C, V}
);

    localparam OP_ADD = 2'b00, OP_SUB = 2'b01, OP_AND = 2'b10, OP_OR = 2'b11;

    wire [16:0] soma = {1'b0, a} + {1'b0, b};
    wire [16:0] subt = {1'b0, a} + {1'b0, ~b} + 17'd1;   // a - b em complemento de 2

    reg c, v;
    always @(*) begin
        c = 1'b0;
        v = 1'b0;
        case (op)
            OP_ADD: begin
                resultado = soma[15:0];
                c = soma[16];
                v = (a[15] == b[15]) && (resultado[15] != a[15]);
            end
            OP_SUB: begin
                resultado = subt[15:0];
                c = subt[16];                               // 1 = nao houve emprestimo
                v = (a[15] != b[15]) && (resultado[15] != a[15]);
            end
            OP_AND: resultado = a & b;
            default: resultado = a | b;                     // OP_OR
        endcase
    end

    wire n = resultado[15];
    wire z = (resultado == 16'd0);
    assign flags = {n, z, c, v};

endmodule
