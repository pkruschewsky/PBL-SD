// ============================================================================
// unidade_controle.v
// Unidade de Controle (UC) do coprocessador: maquina de estados multiciclo.
//
// Le o opcode do IR e gera, a cada ciclo, os SINAIS DE CONTROLE que dizem ao
// datapath o que fazer (no estilo do Patterson & Hennessy: RegWrite, ALUSrc,
// ALUOp...). A UC nao calcula nada: ela so decide quem escreve onde.
//
//            instr_disponivel
//   OCIOSO ------------------> BUSCA --> DECODIFICA --+--> EXECUTA ----------+
//     ^                         ^                     +--> MOVE (2 ou 6 passos)
//     |                         |                     +--> ESPERA_VBLANK -----+
//     |                         +---- ha mais instrucao na fila -------------+
//     +------------------------------- fila vazia ----------------------------+
//
//   BUSCA       : pulsa 'busca' -> unidade de busca copia a instrucao para o IR
//   DECODIFICA  : le o opcode e escolhe o proximo estado (registradores ja
//                 sao lidos pelo banco usando os campos rs/rt do IR)
//   EXECUTA     : ativa a escrita no destino da instrucao (1 ciclo)
//   MOVE        : SPR_MOVE (2 passos: x e y) e POLY_MOVE (6 passos: x0,y0,x1,
//                 y1,x2,y2). Cada passo soma uma coordenada na ULA.
//   ESPERA_VBLANK: WAITV - fica parada ate o pulso de inicio do vblank
//
// Sem pipeline: a instrucao seguinte so e buscada quando a atual termina,
// por isso nao existem hazards de dados ou de controle.
// ============================================================================
`timescale 1ns/1ps
module unidade_controle (
    input  wire       clk,
    input  wire       reset,

    // ---- da unidade de busca ----
    input  wire       instr_disponivel,
    input  wire [4:0] opcode,          // IR[31:27]
    output reg        busca,           // pulso: carregar o IR

    // ---- da unidade de quadro ----
    input  wire       inicio_vblank,

    // ---- sinais de controle para o datapath ----
    output reg        rf_we,           // escreve no banco de registradores
    output reg        rf_fonte,        // dado escrito: 0 = resultado da ULA, 1 = imediato (LI)
    output reg  [1:0] ula_op,          // 00 ADD, 01 SUB, 10 AND, 11 OR
    output reg        ula_fonte_a,     // A da ULA: 0 = rs, 1 = coordenada atual (MOVE)
    output reg  [1:0] ula_fonte_b,     // B da ULA: 0 = rt, 1 = imediato, 2 = rs
    output reg        flags_we,        // guarda as flags da ULA
    output reg        tm_we,           // SET_TILE
    output reg        scroll_we,       // SET_SCROLL
    output reg        poly_vtx_we,     // POLY_VTX
    output reg        poly_cfg_we,     // POLY_CFG
    output reg        poly_coord_we,   // POLY_MOVE: grava a coordenada 'passo'
    output reg        spr_pos_we,      // SPR_POS / fim do SPR_MOVE
    output reg        spr_pos_fonte,   // 0 = (rs, rt), 1 = resultado do MOVE
    output reg        spr_attr_we,     // SPR_ATTR
    output reg        spr_tmp_we,      // SPR_MOVE passo 0: guarda o novo x
    output reg  [2:0] passo,           // passo atual do MOVE

    // ---- estado (vai para o registrador de status) ----
    output wire       busy,
    output reg        erro             // pulso: opcode invalido
);

    // ------------------------------------------------------------------
    // Opcodes da ISA (grupo[31:30] + sub[29:27])
    // ------------------------------------------------------------------
    localparam OP_NOP       = 5'd0,  OP_LI       = 5'd1,  OP_ADD   = 5'd2,  OP_SUB = 5'd3,
               OP_ADDI      = 5'd4,  OP_AND      = 5'd5,  OP_OR    = 5'd6,  OP_WAITV = 5'd7,
               OP_SET_TILE  = 5'd8,  OP_SET_SCROLL = 5'd9,
               OP_POLY_VTX  = 5'd16, OP_POLY_CFG = 5'd17, OP_POLY_MOVE = 5'd18,
               OP_SPR_POS   = 5'd24, OP_SPR_ATTR = 5'd25, OP_SPR_MOVE  = 5'd26;

    // ------------------------------------------------------------------
    // Estados
    // ------------------------------------------------------------------
    localparam S_OCIOSO   = 3'd0, S_BUSCA = 3'd1, S_DECODIFICA = 3'd2,
               S_EXECUTA  = 3'd3, S_MOVE  = 3'd4, S_ESPERA_VBLANK = 3'd5;

    reg [2:0] estado, prox;
    reg [2:0] passo_prox;

    wire opcode_valido = (opcode <= OP_SET_SCROLL) ||
                         (opcode == OP_POLY_VTX) || (opcode == OP_POLY_CFG) || (opcode == OP_POLY_MOVE) ||
                         (opcode == OP_SPR_POS)  || (opcode == OP_SPR_ATTR) || (opcode == OP_SPR_MOVE);

    // depois de terminar uma instrucao: busca a proxima ou fica ociosa
    wire [2:0] fim = instr_disponivel ? S_BUSCA : S_OCIOSO;

    assign busy = (estado != S_OCIOSO);

    // ------------------------------------------------------------------
    // Registradores de estado
    // ------------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            estado <= S_OCIOSO;
            passo  <= 3'd0;
        end else begin
            estado <= prox;
            passo  <= passo_prox;
        end
    end

    // ------------------------------------------------------------------
    // Proximo estado e sinais de controle (combinacional)
    // ------------------------------------------------------------------
    always @(*) begin
        // valores padrao: nada acontece
        prox = estado;          passo_prox = passo;
        busca = 1'b0;           erro = 1'b0;
        rf_we = 1'b0;           rf_fonte = 1'b0;
        ula_op = 2'b00;         ula_fonte_a = 1'b0;   ula_fonte_b = 2'd0;
        flags_we = 1'b0;
        tm_we = 1'b0;           scroll_we = 1'b0;
        poly_vtx_we = 1'b0;     poly_cfg_we = 1'b0;   poly_coord_we = 1'b0;
        spr_pos_we = 1'b0;      spr_pos_fonte = 1'b0; spr_attr_we = 1'b0;  spr_tmp_we = 1'b0;

        case (estado)
            // --------------------------------------------------------
            S_OCIOSO:
                if (instr_disponivel) prox = S_BUSCA;

            // --------------------------------------------------------
            S_BUSCA: begin
                busca = 1'b1;               // IR <- proxima instrucao da fila
                prox  = S_DECODIFICA;
            end

            // --------------------------------------------------------
            S_DECODIFICA: begin
                passo_prox = 3'd0;
                if (!opcode_valido) begin
                    erro = 1'b1;            // opcode reservado: vira NOP e avisa
                    prox = fim;
                end else if (opcode == OP_WAITV)
                    prox = S_ESPERA_VBLANK;
                else if (opcode == OP_SPR_MOVE || opcode == OP_POLY_MOVE)
                    prox = S_MOVE;
                else
                    prox = S_EXECUTA;
            end

            // --------------------------------------------------------
            S_EXECUTA: begin
                case (opcode)
                    OP_LI:   begin rf_we = 1'b1; rf_fonte = 1'b1; end
                    OP_ADD:  begin rf_we = 1'b1; ula_op = 2'b00; flags_we = 1'b1; end
                    OP_SUB:  begin rf_we = 1'b1; ula_op = 2'b01; flags_we = 1'b1; end
                    OP_ADDI: begin rf_we = 1'b1; ula_op = 2'b00; ula_fonte_b = 2'd1; flags_we = 1'b1; end
                    OP_AND:  begin rf_we = 1'b1; ula_op = 2'b10; flags_we = 1'b1; end
                    OP_OR:   begin rf_we = 1'b1; ula_op = 2'b11; flags_we = 1'b1; end
                    OP_SET_TILE:   tm_we       = 1'b1;
                    OP_SET_SCROLL: scroll_we   = 1'b1;
                    OP_POLY_VTX:   poly_vtx_we = 1'b1;
                    OP_POLY_CFG:   poly_cfg_we = 1'b1;
                    OP_SPR_POS:    spr_pos_we  = 1'b1;
                    OP_SPR_ATTR:   spr_attr_we = 1'b1;
                    default: ;                 // NOP
                endcase
                prox = fim;
            end

            // --------------------------------------------------------
            S_MOVE: begin
                ula_op      = 2'b00;           // soma
                ula_fonte_a = 1'b1;            // coordenada atual
                ula_fonte_b = passo[0] ? 2'd0 : 2'd2;   // passo par: x + rs; impar: y + rt
                if (opcode == OP_SPR_MOVE) begin
                    if (passo == 3'd0) begin
                        spr_tmp_we = 1'b1;     // guarda o novo x
                        passo_prox = 3'd1;
                    end else begin
                        spr_pos_we    = 1'b1;  // grava (novo x, novo y)
                        spr_pos_fonte = 1'b1;
                        prox = fim;
                    end
                end else begin                 // POLY_MOVE
                    poly_coord_we = 1'b1;
                    if (passo == 3'd5) prox = fim;
                    else passo_prox = passo + 3'd1;
                end
            end

            // --------------------------------------------------------
            S_ESPERA_VBLANK:
                if (inicio_vblank) prox = fim;

            default: prox = S_OCIOSO;
        endcase
    end

endmodule
