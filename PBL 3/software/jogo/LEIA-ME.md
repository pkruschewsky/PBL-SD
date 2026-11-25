# RUMO AO DIPLOMA — jogo do PBL3

No alto de uma torre de vigas, um professor arremessa peças de hardware
(CPU, memória RAM, HD e disquete). O aluno começa lá embaixo e sobe pelas
escadas desviando das peças até pegar o **diploma**. As peças rolam pelas
vigas em zigue-zague até cair na **caixa de componentes**, no canto inferior
direito: **3 ou mais peças iguais encostadas somem** (pontos em cadeia).
Se a caixa lotar, o aluno é reprovado. Pegando o diploma, passa de semestre:
o professor arremessa mais rápido, as peças descem mais pelas escadas e, a
partir do 3º semestre, entra o disquete. **Pegando o diploma do 10º semestre,
o aluno se forma** e o jogo termina com a tela de formatura.

As peças rolam pelas vigas em zigue-zague e, ao passar por uma escada que
desce, podem descer por ela e cair direto na viga de baixo (20% de chance no
1º semestre, +5% por semestre, até 65%).

## Antes de jogar: desenhos novos na FPGA

Os desenhos do professor, do aluno e das peças ficam na ROM de sprites. O
arquivo `coprocessador_pbl2_quartus/sprites_rom.mif` já vem com eles; basta
**recompilar o projeto no Quartus** e gravar a placa. Para mudar algum
desenho: edite `pbl2_fonte_e_testes/ferramentas/gera_sprites_jogo.py` e rode,
na pasta `pbl2_fonte_e_testes`:

```
python3 ferramentas/gera_sprites_jogo.py
```

## Compilação e execução

Esta pasta (`jogo/`) fica dentro de `software/`, ao lado de `driver/`.
Na placa (DE1-SoC, Linux):

```
cd software/jogo
gcc -O2 -pthread -o diploma jogo.c logica.c fase.c entrada.c efeitos.c -I../driver ../driver/driver_copro.s
sudo ./diploma
```

(ou simplesmente `make`). O `sudo` é necessário porque o driver abre
`/dev/mem` (MMIO) e o jogo lê o teclado e o mouse em `/dev/input/event*`.

## Controles

| Entrada | Ação |
|---|---|
| ← → (ou A/D) | andar |
| ↑ ↓ (ou W/S) | subir e descer escadas |
| ESPAÇO | pular |
| **mouse** | mira; **clique esquerdo** numa peça perto do aluno = desmonta a peça (chave de fenda) |
| P | pausar / continuar |
| R (na pausa) | reiniciar a partida |
| F (na pausa) | pular o semestre (para demonstrar a formatura sem jogar os 10) |
| Q ou ESC | sair / encerrar a partida |
| ENTER | confirmar nas telas |

## Pontuação

- pular por cima de uma peça: **100**
- desmontar uma peça com o clique: **300**
- grupo eliminado na caixa: **500 × tamanho do grupo × cadeia**
- pegar o diploma: **1000 × semestre**

Desmontar uma peça é seguro, mas ela deixa de ir para a caixa, onde
poderia formar um grupo e render muito mais pontos.

## Arquivos

| Arquivo | Conteúdo |
|---|---|
| `jogo.c` | máquina de estados, laço principal (WAITV), envio da cena, medidas |
| `logica.c` | física do aluno, professor, peças, caixa (eliminação de agrupamentos), pontos |
| `fase.c` | desenho da fase com tiles, textos (fonte da ROM), mapa de colisão |
| `entrada.c` | teclado e mouse por `/dev/input`, **cada um na sua thread** |
| `efeitos.c` | tudo que é desenhado com polígonos (retângulos e triângulos) |
| `jogo.h` | constantes, structs e números dos sprites e desenhos |

A aplicação usa **somente** a API do driver (`copro.h` / `driver_copro.s`):
nenhum registrador é acessado diretamente e nenhum pixel é desenhado pelo
ARM, como o PBL03 exige.

## Uso dos recursos do coprocessador

| Recurso | Uso |
|---|---|
| tiles do fundo | vigas, escadas, chão, letreiros e placar (fonte da ROM) |
| sprite 0 | aluno (parado, andando, na escada; espelhado ao virar) |
| sprites 2–5 | professor 32×32 (parado ou arremessando) |
| sprites 6–11 | peças rolando |
| sprites 13–24 | peças paradas na caixa |
| sprites 1 e 12 | diploma e faísca |

**Polígonos** (`efeitos.c`; slot menor fica na frente):

| Slots | Forma | Uso |
|---|---|---|
| 0–1 | retângulos | cursor do mouse (cruz) |
| 2–7 | triângulos | estilhaços que voam quando uma peça é desmontada ou um grupo some na caixa |
| 8–9 | triângulos | raios de fúria do professor quando arremessa (a partir do 3º semestre) |
| 10–11 | triângulos | setas piscando nas escadas (tutorial do 1º semestre) |
| 12 | retângulo | barra de lotação da caixa (verde → amarelo → vermelho) |
| 13 | retângulo | risco de giz na lousa que encolhe até o próximo arremesso |
| 14–15 | retângulos | lousa verde e moldura de madeira atrás do professor |
| 16–31 | triângulos | confetes caindo na tela de formatura |

Os efeitos que se movem (estilhaços e confetes) usam `POLY_MOVE`: o
coprocessador soma o deslocamento nos vértices, e o ARM manda só 3 palavras
por polígono a cada quadro.

## Threads

O programa usa três threads:

- **thread do teclado** e **thread do mouse** (`entrada.c`): cada uma dorme
  em `poll()` até chegar um evento do seu dispositivo, lê o evento e atualiza
  um estado compartilhado (teclas seguradas, teclas apertadas, posição do
  cursor, clique);
- **thread principal** (`jogo.c`): a cada quadro copia esse estado, roda a
  lógica, envia a cena e espera o vblank (`WAITV`).

As três acessam o estado compartilhado sempre com o mesmo *mutex* fechado:
quem chega depois espera alguns microssegundos. Teclado e mouse usados ao
mesmo tempo chegam juntos no mesmo quadro.

Só a thread principal chama o driver: o handshake com o coprocessador
(valid/ack) não pode ser usado por duas threads ao mesmo tempo.

## Medidas (requisito do PBL03)

Ao abrir, o jogo mede a latência média de envio de um comando. Ao sair,
imprime no terminal: latência de envio, quadros processados por segundo,
**tempo de resposta à entrada** (média e pior caso, medidos do momento em
que a thread de entrada recebe o evento até a cena de resposta ser enviada
ao coprocessador) e uso de CPU do processo. Os mesmos números aparecem na
tela de pausa.
