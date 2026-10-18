// ============================================================================
// restaura_tilemap.v
// Copia o MAPA INICIAL (ROM) para a RAM do tilemap toda vez que ha um reset.
//
// A RAM do tilemap so recebe o conteudo do .mif quando a FPGA e programada,
// e o reset nao apaga o que o SET_TILE escreveu nela. Este modulo garante que,
// depois de cada reset, o fundo volte a cena inicial.
//
// Funcionamento (1200 posicoes, 1 por ciclo de 25 MHz = ~48 us):
//   - durante o reset e enquanto copia, "ocupado" = 1: o topo segura o nucleo
//     em reset (nenhuma instrucao roda nem escreve no tilemap ao mesmo tempo);
//   - a ROM tem 2 ciclos de latencia (endereco e saida registrados), entao o
//     endereco de escrita e o "valido" passam por 2 registradores para chegar
//     junto com o dado.
//
//   ciclo:      k        k+1        k+2        k+3
//   cont:       c        c+1        c+2
//   ROM:      (addr c)  (registra)  q = map[c]
//   escrita:                        we, addr=c, data=q  -> grava na borda k+3
// ============================================================================
`timescale 1ns/1ps
module restaura_tilemap #(
    parameter TAMANHO = 1200                  // 40 x 30 tiles
) (
    input  wire        clk,
    input  wire        reset,                 // sincrono, ativo alto

    // ROM com o mapa inicial (2 ciclos de latencia)
    output wire [10:0] rom_addr,
    input  wire [7:0]  rom_data,

    // porta de escrita do tilemap (o topo multiplexa com a do nucleo)
    output wire        we,
    output wire [10:0] wr_addr,
    output wire [7:0]  wr_data,

    output wire        ocupado
);
    reg [10:0] cont;
    reg        ativo;
    reg [10:0] a1, a2;                         // endereco atrasado 1 e 2 ciclos
    reg        v1, v2;                         // "valido" atrasado 1 e 2 ciclos

    always @(posedge clk) begin
        if (reset) begin
            cont  <= 11'd0;
            ativo <= 1'b1;                     // ao sair do reset, comeca a copiar
            v1    <= 1'b0;
            v2    <= 1'b0;
        end else begin
            if (ativo) begin
                cont <= cont + 11'd1;
                if (cont == TAMANHO - 1) ativo <= 1'b0;
            end
            v1 <= ativo;  a1 <= cont;
            v2 <= v1;     a2 <= a1;
        end
    end

    assign rom_addr = cont;
    assign we       = v2 & ~reset;          // escrita "em voo" nao passa durante um novo reset
    assign wr_addr  = a2;
    assign wr_data  = rom_data;
    assign ocupado  = reset | ativo | v1 | v2;
endmodule
