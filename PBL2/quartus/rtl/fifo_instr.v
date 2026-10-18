// ============================================================================
// fifo_instr.v
// Fila de instrucoes do coprocessador (busca assincrona: desacopla o ARM da UC).
//
// Guarda as palavras de 32 bits enviadas pelo ARM ate que a Unidade de
// Controle as busque. Funciona no mesmo clock do nucleo (clk25).
//
// Modo "first-word fall-through": sempre que a fila nao esta vazia, a
// instrucao mais antiga ja aparece em 'dout'. A UC le 'dout' para o IR e
// da um pulso em 'rd_en' (1 ciclo) para descarta-la e avancar para a proxima.
//
// Regras:
//   - escrita com a fila cheia e ignorada (o ARM deve consultar 'full');
//   - leitura com a fila vazia e ignorada;
//   - escrita e leitura no mesmo ciclo sao permitidas (o 'count' nao muda).
//
// Ponteiros com 1 bit extra: quando os bits de endereco sao iguais, o bit
// extra diz se a fila esta vazia (bits extras iguais) ou cheia (diferentes).
// ============================================================================
`timescale 1ns/1ps
module fifo_instr #(
    parameter WIDTH = 32,            // largura da instrucao
    parameter DEPTH = 32,            // numero de posicoes (potencia de 2)
    parameter AW    = 5              // log2(DEPTH)
)(
    input  wire             clk,
    input  wire             reset,   // ativo alto, assincrono

    // Lado de escrita (interface MMIO)
    input  wire             wr_en,
    input  wire [WIDTH-1:0] din,

    // Lado de leitura (Unidade de Controle)
    input  wire             rd_en,
    output wire [WIDTH-1:0] dout,

    // Estado (vai para o registrador de status)
    output wire             empty,
    output wire             full,
    output wire [AW:0]      count    // 0 a DEPTH
);

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [AW:0]      wr_ptr;
    reg [AW:0]      rd_ptr;

    assign empty = (wr_ptr == rd_ptr);
    assign full  = (wr_ptr[AW-1:0] == rd_ptr[AW-1:0]) && (wr_ptr[AW] != rd_ptr[AW]);
    assign count = wr_ptr - rd_ptr;

    // Leitura combinacional: a instrucao mais antiga ja esta disponivel
    assign dout = mem[rd_ptr[AW-1:0]];

    wire do_write = wr_en && !full;
    wire do_read  = rd_en && !empty;

    // Memoria: nao precisa de reset (o conteudo so vale entre rd_ptr e wr_ptr)
    always @(posedge clk) begin
        if (do_write)
            mem[wr_ptr[AW-1:0]] <= din;
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            wr_ptr <= {(AW+1){1'b0}};
            rd_ptr <= {(AW+1){1'b0}};
        end else begin
            if (do_write) wr_ptr <= wr_ptr + 1'b1;
            if (do_read)  rd_ptr <= rd_ptr + 1'b1;
        end
    end

endmodule
