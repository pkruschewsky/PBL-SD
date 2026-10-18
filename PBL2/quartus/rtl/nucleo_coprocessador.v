// ============================================================================
// nucleo_coprocessador.v
// Nucleo programavel do coprocessador: unidade de busca + unidade de controle
// + datapath. Recebe instrucoes do ARM (PIOs) e entrega o barramento de
// comandos graficos para os motores (background, sprites, poligonos).
//
//   PIOs --> [unidade_busca] --IR--> [unidade_controle] --sinais--> [caminho_dados] --> motores
//                                           ^                              |
//                                    inicio_vblank                   spr_cur_x/y
//
// Registrador de status (lido pelo ARM no pio_status):
//   [0] busy   [1] done   [2] fifo_full   [3] fifo_empty   [4] ack
//   [5] vblank [6] err    [11:8] N Z C V  [31:16] fifo_count
// ============================================================================
`timescale 1ns/1ps
module nucleo_coprocessador (
    input  wire        clk,
    input  wire        reset,

    // ---- interface com o ARM (PIOs) ----
    input  wire [31:0] pio_instr,
    input  wire        pio_valid,
    output wire [31:0] status,

    // ---- unidade de quadro ----
    input  wire        vblank,
    input  wire        inicio_vblank,

    // ---- barramento grafico ----
    output wire        tm_wr_en,
    output wire [10:0] tm_wr_addr,
    output wire [7:0]  tm_wr_data,
    output wire [8:0]  scroll_x,
    output wire [7:0]  scroll_y,

    output wire [8:0]  p0_x0, p0_x1, p0_x2,
    output wire [7:0]  p0_y0, p0_y1, p0_y2,
    output wire [1:0]  p0_tipo,
    output wire [7:0]  p0_cor,
    output wire [8:0]  p1_x0, p1_x1, p1_x2,
    output wire [7:0]  p1_y0, p1_y1, p1_y2,
    output wire [1:0]  p1_tipo,
    output wire [7:0]  p1_cor,
    output wire [8:0]  p2_x0, p2_x1, p2_x2,
    output wire [7:0]  p2_y0, p2_y1, p2_y2,
    output wire [1:0]  p2_tipo,
    output wire [7:0]  p2_cor,
    output wire [8:0]  p3_x0, p3_x1, p3_x2,
    output wire [7:0]  p3_y0, p3_y1, p3_y2,
    output wire [1:0]  p3_tipo,
    output wire [7:0]  p3_cor,

    output wire        spr_wr_pos,
    output wire        spr_wr_attr,
    output wire [4:0]  spr_idx,
    output wire [8:0]  spr_x,
    output wire [7:0]  spr_y,
    output wire [11:0] spr_attr,
    input  wire [8:0]  spr_cur_x,
    input  wire [7:0]  spr_cur_y,

    // ---- para depuracao / testbench ----
    output wire [31:0] ir_atual
);

    // ------------------------------------------------------------------
    // Unidade de busca (handshake + FIFO + IR)
    // ------------------------------------------------------------------
    wire        busca, instr_disponivel, ir_valido, ack, fifo_full, fifo_empty;
    wire [31:0] ir;
    wire [5:0]  fifo_count;

    unidade_busca u_busca (
        .clk(clk), .reset(reset),
        .pio_instr(pio_instr), .pio_valid(pio_valid), .ack(ack),
        .busca(busca), .instr_disponivel(instr_disponivel),
        .ir(ir), .ir_valido(ir_valido),
        .fifo_full(fifo_full), .fifo_empty(fifo_empty), .fifo_count(fifo_count)
    );
    assign ir_atual = ir;

    // ------------------------------------------------------------------
    // Unidade de controle
    // ------------------------------------------------------------------
    wire       rf_we, rf_fonte, ula_fonte_a, flags_we, tm_we, scroll_we;
    wire       poly_vtx_we, poly_cfg_we, poly_coord_we;
    wire       spr_pos_we, spr_pos_fonte, spr_attr_we, spr_tmp_we;
    wire [1:0] ula_op, ula_fonte_b;
    wire [2:0] passo;
    wire       busy, erro_pulso;

    unidade_controle u_uc (
        .clk(clk), .reset(reset),
        .instr_disponivel(instr_disponivel), .opcode(ir[31:27]), .busca(busca),
        .inicio_vblank(inicio_vblank),
        .rf_we(rf_we), .rf_fonte(rf_fonte), .ula_op(ula_op),
        .ula_fonte_a(ula_fonte_a), .ula_fonte_b(ula_fonte_b), .flags_we(flags_we),
        .tm_we(tm_we), .scroll_we(scroll_we),
        .poly_vtx_we(poly_vtx_we), .poly_cfg_we(poly_cfg_we), .poly_coord_we(poly_coord_we),
        .spr_pos_we(spr_pos_we), .spr_pos_fonte(spr_pos_fonte), .spr_attr_we(spr_attr_we),
        .spr_tmp_we(spr_tmp_we), .passo(passo),
        .busy(busy), .erro(erro_pulso)
    );

    // ------------------------------------------------------------------
    // Datapath
    // ------------------------------------------------------------------
    wire [3:0] flags;

    caminho_dados u_dp (
        .clk(clk), .reset(reset), .ir(ir),
        .rf_we(rf_we), .rf_fonte(rf_fonte), .ula_op(ula_op),
        .ula_fonte_a(ula_fonte_a), .ula_fonte_b(ula_fonte_b), .flags_we(flags_we),
        .tm_we(tm_we), .scroll_we(scroll_we),
        .poly_vtx_we(poly_vtx_we), .poly_cfg_we(poly_cfg_we), .poly_coord_we(poly_coord_we),
        .spr_pos_we(spr_pos_we), .spr_pos_fonte(spr_pos_fonte), .spr_attr_we(spr_attr_we),
        .spr_tmp_we(spr_tmp_we), .passo(passo),
        .flags(flags),
        .tm_wr_en(tm_wr_en), .tm_wr_addr(tm_wr_addr), .tm_wr_data(tm_wr_data),
        .scroll_x(scroll_x), .scroll_y(scroll_y),
        .p0_x0(p0_x0), .p0_x1(p0_x1), .p0_x2(p0_x2), .p0_y0(p0_y0), .p0_y1(p0_y1), .p0_y2(p0_y2),
        .p0_tipo(p0_tipo), .p0_cor(p0_cor),
        .p1_x0(p1_x0), .p1_x1(p1_x1), .p1_x2(p1_x2), .p1_y0(p1_y0), .p1_y1(p1_y1), .p1_y2(p1_y2),
        .p1_tipo(p1_tipo), .p1_cor(p1_cor),
        .p2_x0(p2_x0), .p2_x1(p2_x1), .p2_x2(p2_x2), .p2_y0(p2_y0), .p2_y1(p2_y1), .p2_y2(p2_y2),
        .p2_tipo(p2_tipo), .p2_cor(p2_cor),
        .p3_x0(p3_x0), .p3_x1(p3_x1), .p3_x2(p3_x2), .p3_y0(p3_y0), .p3_y1(p3_y1), .p3_y2(p3_y2),
        .p3_tipo(p3_tipo), .p3_cor(p3_cor),
        .spr_wr_pos(spr_wr_pos), .spr_wr_attr(spr_wr_attr), .spr_idx(spr_idx),
        .spr_x(spr_x), .spr_y(spr_y), .spr_attr(spr_attr),
        .spr_cur_x(spr_cur_x), .spr_cur_y(spr_cur_y)
    );

    // ------------------------------------------------------------------
    // Registrador de status
    // ------------------------------------------------------------------
    reg err;                                   // fica em 1 ate o reset
    always @(posedge clk or posedge reset) begin
        if (reset)           err <= 1'b0;
        else if (erro_pulso) err <= 1'b1;
    end

    wire done = fifo_empty & ~busy;

    assign status = {10'd0, fifo_count,       // [31:16]
                     4'd0,                    // [15:12]
                     flags,                   // [11:8]  N Z C V
                     1'b0,                    // [7]
                     err,                     // [6]
                     vblank,                  // [5]
                     ack,                     // [4]
                     fifo_empty,              // [3]
                     fifo_full,               // [2]
                     done,                    // [1]
                     busy};                   // [0]

endmodule
