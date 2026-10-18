// ============================================================================
// caminho_dados.v
// Datapath do coprocessador: banco de registradores, ULA, registrador de
// flags, multiplexadores e os registradores das unidades graficas que vivem
// aqui (scroll e os 4 slots de poligono).
//
// Recebe o IR (para tirar os campos rs, rt, imediatos...) e os sinais de
// controle da UC. Entrega o "barramento de comandos graficos" que vai para
// os motores (tilemap, sprites, rasterizadores).
//
// Campos do IR usados:
//   [26:22] A   : rd / indice do sprite / slot / linha do tilemap
//   [21:17] B   : rs          [16:12] C : rt
//   [15:0]      : imediato (LI, ADDI)
//   [21:16]     : coluna (SET_TILE)      [7:0] : tile / cor
//   [1:0]       : vertice (POLY_VTX)     [9:8] : tipo (POLY_CFG)
//   [11:0]      : atributos (SPR_ATTR) = {BACK, FY, FX, EN, tile[7:0]}
// ============================================================================
`timescale 1ns/1ps
module caminho_dados (
    input  wire        clk,
    input  wire        reset,

    input  wire [31:0] ir,

    // ---- sinais de controle (da UC) ----
    input  wire        rf_we,
    input  wire        rf_fonte,
    input  wire [1:0]  ula_op,
    input  wire        ula_fonte_a,
    input  wire [1:0]  ula_fonte_b,
    input  wire        flags_we,
    input  wire        tm_we,
    input  wire        scroll_we,
    input  wire        poly_vtx_we,
    input  wire        poly_cfg_we,
    input  wire        poly_coord_we,
    input  wire        spr_pos_we,
    input  wire        spr_pos_fonte,
    input  wire        spr_attr_we,
    input  wire        spr_tmp_we,
    input  wire [2:0]  passo,

    // ---- registrador de status ----
    output reg  [3:0]  flags,            // {N, Z, C, V}

    // ---- barramento grafico: background ----
    output wire        tm_wr_en,
    output wire [10:0] tm_wr_addr,
    output wire [7:0]  tm_wr_data,
    output reg  [8:0]  scroll_x,
    output reg  [7:0]  scroll_y,

    // ---- barramento grafico: poligonos (4 slots) ----
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

    // ---- barramento grafico: sprites ----
    output wire        spr_wr_pos,
    output wire        spr_wr_attr,
    output wire [4:0]  spr_idx,
    output wire [8:0]  spr_x,
    output wire [7:0]  spr_y,
    output wire [11:0] spr_attr,
    input  wire [8:0]  spr_cur_x,        // posicao atual do sprite spr_idx (leitura)
    input  wire [7:0]  spr_cur_y
);

    // ------------------------------------------------------------------
    // Campos do IR
    // ------------------------------------------------------------------
    wire [4:0]  campo_a = ir[26:22];
    wire [4:0]  rs      = ir[21:17];
    wire [4:0]  rt      = ir[16:12];
    wire [15:0] imm16   = ir[15:0];
    wire [4:0]  opcode  = ir[31:27];

    // ------------------------------------------------------------------
    // Banco de registradores
    // ------------------------------------------------------------------
    wire [15:0] val_rs, val_rt, resultado_ula;
    wire [15:0] dado_rf = rf_fonte ? imm16 : resultado_ula;

    banco_registradores u_banco (
        .clk(clk), .reset(reset),
        .ra1(rs), .ra2(rt), .rd1(val_rs), .rd2(val_rt),
        .we(rf_we), .wa(campo_a), .wd(dado_rf)
    );

    // ------------------------------------------------------------------
    // Poligonos: 4 slots x (3 vertices + tipo + cor)
    // ------------------------------------------------------------------
    reg [8:0] vx [0:3][0:2];
    reg [7:0] vy [0:3][0:2];
    reg [1:0] tipo [0:3];
    reg [7:0] cor  [0:3];

    wire [1:0] slot       = campo_a[1:0];
    wire       slot_ok    = (campo_a[4:2] == 3'd0);     // so existem os slots 0 a 3
    wire [1:0] vtx        = ir[1:0];
    wire [1:0] vtx_passo  = passo[2:1];                 // passo 0,1->v0  2,3->v1  4,5->v2

    // coordenada atual usada pelos MOVE (entrada A da ULA)
    reg [15:0] coord_atual;
    always @(*) begin
        if (opcode == 5'd26)                            // SPR_MOVE
            coord_atual = passo[0] ? {8'd0, spr_cur_y} : {7'd0, spr_cur_x};
        else                                            // POLY_MOVE
            coord_atual = passo[0] ? {8'd0, vy[slot][vtx_passo]} : {7'd0, vx[slot][vtx_passo]};
    end

    // ------------------------------------------------------------------
    // ULA
    // ------------------------------------------------------------------
    reg  [15:0] ula_a, ula_b;
    wire [3:0]  flags_ula;
    always @(*) begin
        ula_a = ula_fonte_a ? coord_atual : val_rs;
        case (ula_fonte_b)
            2'd1:    ula_b = imm16;                     // ADDI
            2'd2:    ula_b = val_rs;                    // MOVE, coordenada x
            default: ula_b = val_rt;
        endcase
    end

    ula u_ula (.a(ula_a), .b(ula_b), .op(ula_op), .resultado(resultado_ula), .flags(flags_ula));

    // ------------------------------------------------------------------
    // Registradores de estado: flags, scroll, poligonos, x temporario
    // ------------------------------------------------------------------
    reg [8:0] spr_tmp_x;
    integer s, v;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            flags     <= 4'd0;
            scroll_x  <= 9'd0;
            scroll_y  <= 8'd0;
            spr_tmp_x <= 9'd0;
            for (s = 0; s < 4; s = s + 1) begin
                tipo[s] <= 2'd0;                        // OFF
                cor[s]  <= 8'd0;
                for (v = 0; v < 3; v = v + 1) begin
                    vx[s][v] <= 9'd0;
                    vy[s][v] <= 8'd0;
                end
            end
        end else begin
            // AND/OR atualizam so N e Z; ADD/SUB/ADDI atualizam N Z C V
            if (flags_we)
                flags <= (ula_op[1]) ? {flags_ula[3:2], flags[1:0]} : flags_ula;

            if (scroll_we) begin
                scroll_x <= val_rs[8:0];
                scroll_y <= val_rt[7:0];
            end

            if (poly_vtx_we && slot_ok && vtx != 2'd3) begin
                vx[slot][vtx] <= val_rs[8:0];
                vy[slot][vtx] <= val_rt[7:0];
            end

            if (poly_cfg_we && slot_ok) begin
                tipo[slot] <= ir[9:8];
                cor[slot]  <= ir[7:0];
            end

            if (poly_coord_we && slot_ok) begin
                if (passo[0]) vy[slot][vtx_passo] <= resultado_ula[7:0];
                else          vx[slot][vtx_passo] <= resultado_ula[8:0];
            end

            if (spr_tmp_we)
                spr_tmp_x <= resultado_ula[8:0];
        end
    end

    // ------------------------------------------------------------------
    // Saidas para o background
    // ------------------------------------------------------------------
    wire [10:0] linha = {6'd0, campo_a};
    assign tm_wr_en   = tm_we;
    assign tm_wr_addr = (linha << 5) + (linha << 3) + {5'd0, ir[21:16]};   // lin*40 + col
    assign tm_wr_data = ir[7:0];

    // ------------------------------------------------------------------
    // Saidas para os poligonos
    // ------------------------------------------------------------------
    assign p0_x0 = vx[0][0]; assign p0_x1 = vx[0][1]; assign p0_x2 = vx[0][2];
    assign p0_y0 = vy[0][0]; assign p0_y1 = vy[0][1]; assign p0_y2 = vy[0][2];
    assign p0_tipo = tipo[0]; assign p0_cor = cor[0];
    assign p1_x0 = vx[1][0]; assign p1_x1 = vx[1][1]; assign p1_x2 = vx[1][2];
    assign p1_y0 = vy[1][0]; assign p1_y1 = vy[1][1]; assign p1_y2 = vy[1][2];
    assign p1_tipo = tipo[1]; assign p1_cor = cor[1];
    assign p2_x0 = vx[2][0]; assign p2_x1 = vx[2][1]; assign p2_x2 = vx[2][2];
    assign p2_y0 = vy[2][0]; assign p2_y1 = vy[2][1]; assign p2_y2 = vy[2][2];
    assign p2_tipo = tipo[2]; assign p2_cor = cor[2];
    assign p3_x0 = vx[3][0]; assign p3_x1 = vx[3][1]; assign p3_x2 = vx[3][2];
    assign p3_y0 = vy[3][0]; assign p3_y1 = vy[3][1]; assign p3_y2 = vy[3][2];
    assign p3_tipo = tipo[3]; assign p3_cor = cor[3];

    // ------------------------------------------------------------------
    // Saidas para os sprites
    // ------------------------------------------------------------------
    assign spr_wr_pos  = spr_pos_we;
    assign spr_wr_attr = spr_attr_we;
    assign spr_idx     = campo_a;
    assign spr_x       = spr_pos_fonte ? spr_tmp_x : val_rs[8:0];
    assign spr_y       = spr_pos_fonte ? resultado_ula[7:0] : val_rt[7:0];
    assign spr_attr    = ir[11:0];

endmodule
