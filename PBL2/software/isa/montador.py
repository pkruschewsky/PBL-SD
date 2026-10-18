#!/usr/bin/env python3
# ============================================================================
# montador.py - MONTADOR (assembler) da ISA do coprocessador grafico
#
# Traduz um programa escrito no Assembly da NOSSA ISA (arquivo .asm) para
# codigo de maquina (palavras de 32 bits), seguindo o formato da ISA.
#
# Uso:
#   python3 montador.py demo.asm                 -> gera demo.lst e programa_isa.s
#   python3 montador.py demo.asm -s saida.s -l saida.lst -x saida.hex
#
# Saidas:
#   .lst : listagem (endereco, palavra em hex, linha original) - para conferir/estudar
#   .s   : tabelas ".word" em Assembly ARM, uma por bloco, para o programa ARM enviar
#   .hex : (opcional) uma palavra por linha, para simulacao
#
# ---------------------------------------------------------------------------
# SINTAXE DO ASSEMBLY DA ISA
# ---------------------------------------------------------------------------
#   ; comentario ate o fim da linha
#   .equ  NOME, valor          define uma constante (ex.: .equ VERMELHO, 0xE0)
#   .bloco nome                inicia um bloco de instrucoes (ver abaixo)
#
#   MNEMONICO operando, operando, ...      (maiusculas/minusculas tanto faz)
#
#   Registradores : r0 .. r31   (r0 vale sempre 0)
#   Numeros       : 160   -2   0xE0   0b11100000   ou o nome de uma .equ
#
#   NOP
#   LI         rd, imm16                 imm de -32768 a 65535
#   ADD        rd, rs, rt
#   SUB        rd, rs, rt
#   ADDI       rd, rs, imm17             imm de -65536 a 65535
#   AND        rd, rs, rt
#   OR         rd, rs, rt
#   WAITV
#   SET_TILE   lin, col, tile            lin 0-29, col 0-39, tile 0-255
#   SET_SCROLL rs, rt                    scroll_x <- rs, scroll_y <- rt
#   POLY_VTX   slot, v, rs, rt           slot 0-3, vertice v 0-2
#   POLY_CFG   slot, tipo, cor           tipo = OFF | RECT | TRI, cor 0-255 (RGB332)
#   POLY_MOVE  slot, rs, rt
#   SPR_POS    n, rs, rt                 n 0-31
#   SPR_ATTR   n, tile [, EN] [, FX] [, FY] [, BACK]
#   SPR_MOVE   n, rs, rt
#
# BLOCOS: como as instrucoes vem do ARM (busca ASSINCRONA, por FIFO) e a ISA
# nao tem desvios, quem decide QUANDO cada trecho roda e o ARM. Por isso o programa e dividido em blocos com nome
# (.bloco cena, .bloco quadro, ...). O montador gera, para cada bloco, os
# rotulos isa_<nome> e isa_<nome>_fim no arquivo .s; o programa ARM envia
# o bloco inteiro com:  ldr r0,=isa_<nome> / ldr r1,=isa_<nome>_fim / bl copro_envia_bloco
# ============================================================================
import re
import sys
import argparse

OPCODES = {
    "NOP": 0, "LI": 1, "ADD": 2, "SUB": 3, "ADDI": 4, "AND": 5, "OR": 6, "WAITV": 7,
    "SET_TILE": 8, "SET_SCROLL": 9,
    "POLY_VTX": 16, "POLY_CFG": 17, "POLY_MOVE": 18,
    "SPR_POS": 24, "SPR_ATTR": 25, "SPR_MOVE": 26,
}
TIPOS_POLIGONO = {"OFF": 0, "RECT": 1, "TRI": 2}
FLAGS_SPRITE = {"EN": 8, "FX": 9, "FY": 10, "BACK": 11}   # bit de cada flag na palavra


class ErroMontagem(Exception):
    pass


def campos(op, a=0, b=0, c=0):
    """Monta os campos fixos: op[31:27] A[26:22] B[21:17] C[16:12]."""
    return (op << 27) | (a << 22) | (b << 17) | (c << 12)


class Montador:
    def __init__(self):
        self.constantes = {}
        self.blocos = []          # lista de (nome, [(palavra, linha_num, texto)])

    # ---------------- leitura de operandos ----------------
    def numero(self, txt, minimo, maximo, oque):
        t = txt.strip()
        sinal, nome = (-1, t[1:].strip()) if t.startswith("-") else (1, t)
        if nome.upper() in self.constantes:          # constante (.equ), com ou sem '-'
            v = sinal * self.constantes[nome.upper()]
        else:
            try:
                v = int(t, 0)       # aceita 160, -2, 0xE0, 0b1010
            except ValueError:
                raise ErroMontagem(f"'{t}' nao e um numero valido para {oque}")
        if not (minimo <= v <= maximo):
            raise ErroMontagem(f"{oque} = {v} fora da faixa ({minimo} a {maximo})")
        return v

    @staticmethod
    def registrador(txt):
        m = re.fullmatch(r"[rR](\d{1,2})", txt.strip())
        if not m or int(m.group(1)) > 31:
            raise ErroMontagem(f"'{txt.strip()}' nao e um registrador (use r0 a r31)")
        return int(m.group(1))

    @staticmethod
    def quantidade(ops, n, sintaxe):
        if len(ops) != n:
            raise ErroMontagem(f"esperado {n} operando(s): {sintaxe}")

    # ---------------- uma instrucao -> uma palavra ----------------
    def monta_instrucao(self, mnem, ops):
        if mnem not in OPCODES:
            raise ErroMontagem(f"instrucao desconhecida '{mnem}'")
        op = OPCODES[mnem]
        R, N = self.registrador, self.numero

        if mnem in ("NOP", "WAITV"):
            self.quantidade(ops, 0, mnem)
            return campos(op)
        if mnem == "LI":
            self.quantidade(ops, 2, "LI rd, imm16")
            return campos(op, R(ops[0])) | (N(ops[1], -32768, 65535, "imm16") & 0xFFFF)
        if mnem in ("ADD", "SUB", "AND", "OR"):
            self.quantidade(ops, 3, f"{mnem} rd, rs, rt")
            return campos(op, R(ops[0]), R(ops[1]), R(ops[2]))
        if mnem == "ADDI":
            self.quantidade(ops, 3, "ADDI rd, rs, imm17")
            return campos(op, R(ops[0]), R(ops[1])) | (N(ops[2], -65536, 65535, "imm17") & 0x1FFFF)
        if mnem == "SET_TILE":
            self.quantidade(ops, 3, "SET_TILE lin, col, tile")
            return (campos(op, N(ops[0], 0, 29, "linha")) | (N(ops[1], 0, 39, "coluna") << 16)
                    | N(ops[2], 0, 255, "tile"))
        if mnem == "SET_SCROLL":
            self.quantidade(ops, 2, "SET_SCROLL rs, rt")
            return campos(op, 0, R(ops[0]), R(ops[1]))
        if mnem == "POLY_VTX":
            self.quantidade(ops, 4, "POLY_VTX slot, v, rs, rt")
            return (campos(op, N(ops[0], 0, 3, "slot"), R(ops[2]), R(ops[3]))
                    | N(ops[1], 0, 2, "vertice"))
        if mnem == "POLY_CFG":
            self.quantidade(ops, 3, "POLY_CFG slot, tipo, cor")
            tipo = ops[1].strip().upper()
            if tipo not in TIPOS_POLIGONO:
                raise ErroMontagem(f"tipo de poligono '{ops[1].strip()}' invalido (use OFF, RECT ou TRI)")
            return (campos(op, N(ops[0], 0, 3, "slot")) | (TIPOS_POLIGONO[tipo] << 8)
                    | N(ops[2], 0, 255, "cor"))
        if mnem in ("POLY_MOVE",):
            self.quantidade(ops, 3, "POLY_MOVE slot, rs, rt")
            return campos(op, N(ops[0], 0, 3, "slot"), R(ops[1]), R(ops[2]))
        if mnem in ("SPR_POS", "SPR_MOVE"):
            self.quantidade(ops, 3, f"{mnem} n, rs, rt")
            return campos(op, N(ops[0], 0, 31, "sprite"), R(ops[1]), R(ops[2]))
        if mnem == "SPR_ATTR":
            if len(ops) < 2:
                raise ErroMontagem("esperado: SPR_ATTR n, tile [, EN] [, FX] [, FY] [, BACK]")
            palavra = campos(op, N(ops[0], 0, 31, "sprite")) | N(ops[1], 0, 255, "tile")
            for f in ops[2:]:
                f = f.strip().upper()
                if f not in FLAGS_SPRITE:
                    raise ErroMontagem(f"flag de sprite '{f}' invalida (use EN, FX, FY, BACK)")
                palavra |= 1 << FLAGS_SPRITE[f]
            return palavra
        raise ErroMontagem(f"instrucao '{mnem}' sem regra de montagem")   # nao deve acontecer

    # ---------------- arquivo inteiro ----------------
    def monta_texto(self, texto):
        erros = []
        bloco_atual = None
        for num, linha_orig in enumerate(texto.splitlines(), start=1):
            linha = linha_orig.split(";", 1)[0].strip()
            if not linha:
                continue
            try:
                partes = linha.split(None, 1)
                mnem = partes[0].upper()
                resto = partes[1] if len(partes) > 1 else ""
                ops = [o.strip() for o in resto.split(",")] if resto.strip() else []

                if mnem == ".EQU":
                    self.quantidade(ops, 2, ".equ NOME, valor")
                    nome = ops[0].upper()
                    if not re.fullmatch(r"[A-Z_][A-Z0-9_]*", nome) or nome in OPCODES:
                        raise ErroMontagem(f"nome de constante invalido '{ops[0]}'")
                    self.constantes[nome] = self.numero(ops[1], -65536, 65535, nome)
                    continue
                if mnem == ".BLOCO":
                    self.quantidade(ops, 1, ".bloco nome")
                    nome = ops[0].lower()
                    if not re.fullmatch(r"[a-z_][a-z0-9_]*", nome):
                        raise ErroMontagem(f"nome de bloco invalido '{ops[0]}'")
                    if any(n == nome for n, _ in self.blocos):
                        raise ErroMontagem(f"bloco '{nome}' repetido")
                    bloco_atual = (nome, [])
                    self.blocos.append(bloco_atual)
                    continue
                if mnem.startswith("."):
                    raise ErroMontagem(f"diretiva desconhecida '{partes[0]}'")
                if bloco_atual is None:
                    raise ErroMontagem("instrucao fora de bloco (comece com '.bloco nome')")
                palavra = self.monta_instrucao(mnem, ops)
                bloco_atual[1].append((palavra, num, linha_orig.strip()))
            except ErroMontagem as e:
                erros.append(f"linha {num}: {e}\n    {linha_orig.strip()}")
        for nome, instrs in self.blocos:
            if not instrs and not erros:
                erros.append(f"bloco '{nome}' esta vazio")
        return erros

    # ---------------- geracao das saidas ----------------
    def gera_listagem(self, origem):
        out = [f"; Listagem gerada por montador.py a partir de {origem}",
               "; end. = posicao da palavra dentro do bloco",
               ";", "; end.  palavra     linha  fonte"]
        total = 0
        for nome, instrs in self.blocos:
            out.append(f"\n; ===== bloco {nome}  ({len(instrs)} instrucoes) =====")
            for i, (p, num, txt) in enumerate(instrs):
                out.append(f"  {i:3d}  {p:08X}   {num:4d}   {txt}")
            total += len(instrs)
        out.append(f"\n; total: {total} instrucoes em {len(self.blocos)} blocos")
        return "\n".join(out) + "\n"

    def gera_arm(self, origem):
        out = ["@ ==========================================================================",
               f"@ programa_isa.s - GERADO AUTOMATICAMENTE por montador.py a partir de {origem}",
               "@ NAO EDITE A MAO: altere o .asm e rode o montador de novo.",
               "@",
               "@ Cada bloco vira uma tabela de palavras de 32 bits (codigo de maquina da",
               "@ NOSSA ISA). O ARM nao executa estas palavras: ele so as le da memoria e",
               "@ as envia, uma a uma, para o coprocessador pelos PIOs.",
               "@ ==========================================================================",
               "        .section .rodata",
               "        .align 2"]
        for nome, instrs in self.blocos:
            out.append("")
            out.append(f"        .global isa_{nome}, isa_{nome}_fim")
            out.append(f"isa_{nome}:")
            for p, num, txt in instrs:
                out.append(f"        .word 0x{p:08X}      @ {txt}")
            out.append(f"isa_{nome}_fim:")
        out.append("")
        out.append('        .section .note.GNU-stack, "", %progbits')
        return "\n".join(out) + "\n"

    def gera_hex(self):
        return "".join(f"{p:08X}\n" for _, instrs in self.blocos for p, _, _ in instrs)


def main():
    ap = argparse.ArgumentParser(description="Montador da ISA do coprocessador grafico")
    ap.add_argument("fonte", help="programa em Assembly da ISA (.asm)")
    ap.add_argument("-s", "--saida-arm", default="programa_isa.s", help="arquivo .s com as tabelas (padrao: programa_isa.s)")
    ap.add_argument("-l", "--listagem", help="arquivo de listagem (padrao: <fonte>.lst)")
    ap.add_argument("-x", "--hex", help="gera tambem um .hex com uma palavra por linha")
    args = ap.parse_args()

    with open(args.fonte, encoding="utf-8") as f:
        texto = f.read()
    m = Montador()
    erros = m.monta_texto(texto)
    if erros:
        print(f"{len(erros)} erro(s) em {args.fonte}:", file=sys.stderr)
        for e in erros:
            print("  " + e, file=sys.stderr)
        sys.exit(1)

    nome_fonte = args.fonte.replace("\\", "/").split("/")[-1]
    lst = args.listagem or re.sub(r"\.[^.]*$", "", args.fonte) + ".lst"
    with open(lst, "w", encoding="utf-8") as f:
        f.write(m.gera_listagem(nome_fonte))
    with open(args.saida_arm, "w", encoding="utf-8") as f:
        f.write(m.gera_arm(nome_fonte))
    if args.hex:
        with open(args.hex, "w") as f:
            f.write(m.gera_hex())

    total = sum(len(i) for _, i in m.blocos)
    print(f"OK: {total} instrucoes em {len(m.blocos)} blocos -> {args.saida_arm}, {lst}")
    for nome, instrs in m.blocos:
        print(f"   {nome:16s} {len(instrs):3d} instrucoes")


if __name__ == "__main__":
    main()
