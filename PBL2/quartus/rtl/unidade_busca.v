// ============================================================================
// unidade_busca.v
// Unidade de busca de instrucoes (busca ASSINCRONA) + Registrador de Instrucao.
// Assincrona: o ARM escreve na FIFO no ritmo dele (handshake valid/ack) e a UC
// busca a proxima instrucao na FIFO quando termina a anterior, no ritmo dela.
//
// Caminho da instrucao:
//
//   ARM --(ponte)--> PIOs --> [ receptor ] --> [ FIFO ] --> [ IR ] --> UC
//                     pio_instr   handshake      32 x 32      32 bits
//                     pio_valid   valid / ack
//
// 1) Receptor (handshake de 4 fases com o ARM):
//      - o ARM escreve a palavra em pio_instr e depois pio_valid = 1;
//      - 'pio_valid' vem de outro dominio de clock (PIO, 50 MHz), entao e
//        sincronizado com 2 flip-flops antes de ser usado em clk25;
//      - ao ver valid = 1 (e havendo espaco na fila), grava pio_instr na FIFO
//        e sobe 'ack';
//      - o ARM ve ack = 1 e baixa valid; o receptor ve valid = 0 e baixa ack.
//    A palavra pio_instr fica estavel enquanto valid = 1, por isso pode ser
//    copiada com seguranca no momento em que o valid sincronizado e visto.
//    Se a fila estiver cheia, o ack so sobe quando abrir espaco (nada se perde).
//
// 2) FIFO: guarda as instrucoes ate a UC busca-las (fifo_instr.v).
//
// 3) IR: quando a UC pulsa 'busca' (estado BUSCA), a instrucao mais antiga
//    da fila e copiada para o IR e removida da fila. No ciclo seguinte
//    'ir_valido' fica em 1 por um ciclo, avisando a UC que o IR tem uma
//    instrucao nova para decodificar.
// ============================================================================
`timescale 1ns/1ps
module unidade_busca (
    input  wire        clk,             // clk25 do nucleo
    input  wire        reset,           // ativo alto

    // ---- Lado ARM (vem dos PIOs) ----
    input  wire [31:0] pio_instr,       // palavra da instrucao
    input  wire        pio_valid,       // bit 0 do pio_ctrl
    output reg         ack,             // vai para o pio_status (bit 4)

    // ---- Lado Unidade de Controle ----
    input  wire        busca,           // pulso de 1 ciclo: carregar o IR
    output wire        instr_disponivel,// ha instrucao esperando na fila
    output reg  [31:0] ir,              // Registrador de Instrucao
    output reg         ir_valido,       // 1 ciclo apos uma busca bem-sucedida

    // ---- Estado da fila (vai para o registrador de status) ----
    output wire        fifo_full,
    output wire        fifo_empty,
    output wire [5:0]  fifo_count
);

    // ------------------------------------------------------------------
    // Sincronizador de 2 flip-flops para o valid (cruzamento de clock)
    // ------------------------------------------------------------------
    reg valid_s1, valid_s2;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            valid_s1 <= 1'b0;
            valid_s2 <= 1'b0;
        end else begin
            valid_s1 <= pio_valid;
            valid_s2 <= valid_s1;
        end
    end

    // ------------------------------------------------------------------
    // Receptor: maquina de 2 estados do handshake
    // ------------------------------------------------------------------
    localparam ESPERA_VALID  = 1'b0;    // aguardando o ARM subir valid
    localparam ESPERA_BAIXAR = 1'b1;    // ack dado; aguardando o ARM baixar valid

    reg  estado;
    wire grava_fifo = (estado == ESPERA_VALID) && valid_s2 && !fifo_full;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            estado <= ESPERA_VALID;
            ack    <= 1'b0;
        end else begin
            case (estado)
                ESPERA_VALID:
                    if (grava_fifo) begin       // palavra entra na fila
                        ack    <= 1'b1;
                        estado <= ESPERA_BAIXAR;
                    end
                ESPERA_BAIXAR:
                    if (!valid_s2) begin        // ARM terminou o handshake
                        ack    <= 1'b0;
                        estado <= ESPERA_VALID;
                    end
            endcase
        end
    end

    // ------------------------------------------------------------------
    // Fila de instrucoes
    // ------------------------------------------------------------------
    wire [31:0] fifo_dout;
    wire        le_fifo = busca && !fifo_empty;

    fifo_instr #(.WIDTH(32), .DEPTH(32), .AW(5)) u_fifo (
        .clk   (clk),
        .reset (reset),
        .wr_en (grava_fifo),
        .din   (pio_instr),
        .rd_en (le_fifo),
        .dout  (fifo_dout),
        .empty (fifo_empty),
        .full  (fifo_full),
        .count (fifo_count)
    );

    assign instr_disponivel = !fifo_empty;

    // ------------------------------------------------------------------
    // Registrador de Instrucao (IR)
    // ------------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ir        <= 32'd0;             // 0 = NOP
            ir_valido <= 1'b0;
        end else begin
            ir_valido <= le_fifo;
            if (le_fifo)
                ir <= fifo_dout;
        end
    end

endmodule
