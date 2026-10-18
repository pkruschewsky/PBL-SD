// ============================================================================
// banco_registradores.v
// Banco de registradores do coprocessador: 32 registradores de 16 bits.
//
//   - 2 portas de leitura combinacionais (rs e rt), como no MIPS:
//     o valor aparece na saida no mesmo ciclo em que o endereco muda.
//   - 1 porta de escrita sincrona (rd), na borda de subida do clock.
//   - r0 vale sempre 0: escritas em r0 sao ignoradas e a leitura de r0
//     devolve 0. Isso permite, por exemplo, SET_SCROLL r0, r0 (posicao 0).
//   - Reset: todos os registradores voltam a 0.
// ============================================================================
`timescale 1ns/1ps
module banco_registradores (
    input  wire        clk,
    input  wire        reset,      // ativo alto, assincrono

    // Leitura (combinacional)
    input  wire [4:0]  ra1,        // endereco rs
    input  wire [4:0]  ra2,        // endereco rt
    output wire [15:0] rd1,        // valor de rs
    output wire [15:0] rd2,        // valor de rt

    // Escrita (sincrona)
    input  wire        we,         // habilita escrita
    input  wire [4:0]  wa,         // endereco rd
    input  wire [15:0] wd          // dado a escrever
);

    reg [15:0] regs [1:31];        // r0 nao existe fisicamente: e sempre 0
    integer i;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 1; i < 32; i = i + 1)
                regs[i] <= 16'd0;
        end else if (we && (wa != 5'd0)) begin
            regs[wa] <= wd;
        end
    end

    assign rd1 = (ra1 == 5'd0) ? 16'd0 : regs[ra1];
    assign rd2 = (ra2 == 5'd0) ? 16'd0 : regs[ra2];

endmodule
