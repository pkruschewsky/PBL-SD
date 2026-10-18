// ============================================================================
// painel_depuracao.v
// Mostra o estado do coprocessador nos LEDs e displays da DE1-SoC.
// Nao faz parte do coprocessador em si: e uma ajuda para testes na placa.
//
//   HEX5..HEX0 : instrucao no IR (a ultima buscada)
//                SW[0] = 0 -> IR[31:8]   SW[0] = 1 -> IR[23:0]
//   LEDR[0] busy   LEDR[1] done   LEDR[2] fila cheia   LEDR[3] fila vazia
//   LEDR[4] ack    LEDR[5] vblank LEDR[6] err
//   LEDR[9:7] flags N Z C
// ============================================================================
`timescale 1ns/1ps
module painel_depuracao (
    input  wire [31:0] ir,
    input  wire [31:0] status,
    input  wire        sel_baixo,        // SW[0]
    output wire [9:0]  LEDR,
    output wire [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5
);
    assign LEDR = {status[11:9], status[6:0]};

    wire [23:0] mostra = sel_baixo ? ir[23:0] : ir[31:8];
    hex7seg h0 (.valor(mostra[3:0]),   .seg(HEX0));
    hex7seg h1 (.valor(mostra[7:4]),   .seg(HEX1));
    hex7seg h2 (.valor(mostra[11:8]),  .seg(HEX2));
    hex7seg h3 (.valor(mostra[15:12]), .seg(HEX3));
    hex7seg h4 (.valor(mostra[19:16]), .seg(HEX4));
    hex7seg h5 (.valor(mostra[23:20]), .seg(HEX5));
endmodule

// valor de 4 bits -> display de 7 segmentos da DE1-SoC (ativo baixo), seg = {g,f,e,d,c,b,a}
module hex7seg (
    input  wire [3:0] valor,
    output reg  [6:0] seg
);
    always @(*) begin
        case (valor)
            4'h0: seg = 7'b1000000;  4'h1: seg = 7'b1111001;
            4'h2: seg = 7'b0100100;  4'h3: seg = 7'b0110000;
            4'h4: seg = 7'b0011001;  4'h5: seg = 7'b0010010;
            4'h6: seg = 7'b0000010;  4'h7: seg = 7'b1111000;
            4'h8: seg = 7'b0000000;  4'h9: seg = 7'b0010000;
            4'hA: seg = 7'b0001000;  4'hB: seg = 7'b0000011;
            4'hC: seg = 7'b1000110;  4'hD: seg = 7'b0100001;
            4'hE: seg = 7'b0000110;  default: seg = 7'b0001110;
        endcase
    end
endmodule
