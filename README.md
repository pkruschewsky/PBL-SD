# Coprocessador Gráfico VGA Multicamadas em FPGA
TEC499 - MI SISTEMAS DIGITAIS

*Componentes do grupo:*
* Davi Freitas Queiroz
* Pedro Haywanon Santos Araujo
* Pedro Kruschewsky Lordelo

*Tutor:* Angelo Amâncio Duarte
*Universidade Estadual de Feira de Santana (UEFS)*

---

## 1. Introdução

Os coprocessadores gráficos constituem blocos fundamentais de sistemas computacionais interativos, sendo os responsáveis por assumir a carga exaustiva da renderização visual e liberar a Unidade Central de Processamento (CPU) para a execução da lógica principal da aplicação.

Este projeto teve como objetivo o desenvolvimento de um núcleo gráfico dedicado em hardware (FPGA), inspirado na arquitetura clássica de consoles de 16 bits. A solução foi projetada para sintetizar um sinal de vídeo VGA (640×480 a 60 Hz) através da orquestração de múltiplas camadas visuais simultâneas: um plano de fundo baseado em blocos (*tilemap*), entidades móveis independentes (*sprites*) e um rasterizador procedural de polígonos.

A implementação foi realizada inteiramente em linguagem Verilog, utilizando a plataforma DE1-SoC (Intel Cyclone V). Um aspecto central do projeto foi a adoção de uma arquitetura de renderização *on-the-fly* — descartando a utilização de um *framebuffer* estático completo para otimização de recursos. Essa decisão exigiu o gerenciamento preciso de latências, o uso de memórias de forma síncrona/assíncrona e a orquestração de um *datapath* dedicado.

O sistema final foi feito com o propósito de preparar o núcleo de hardware para, em etapas posteriores, atuar de forma autônoma sob o comando de um driver em Assembly ARM e uma aplicação em linguagem C.

---

## 2. Especificação de Hardware

| Item | Valor |
|---|---|
| Placa de desenvolvimento | Terasic DE1-SoC |
| FPGA | Intel/Altera Cyclone V — `5CSEMA5F31C6` |
| Ferramenta de síntese | Quartus Prime 23.1std.0 Build 991 (SC Lite Edition) |
| Clock de entrada | 50 MHz (`CLOCK_50`), dividido internamente para 25 MHz via `clock_divider.v` |
| Periféricos usados na demonstração | `SW[9:0]`, `KEY[3:0]`, saída VGA (`VGA_R/G/B`, `VGA_HS/VS`, `VGA_CLK`, `VGA_SYNC_N`, `VGA_BLANK_N`) |

---

## 3. Fundamentação teórica

Para atender aos requisitos da construção do núcleo gráfico, foi necessário entender e pesquisar sobre a arquitetura dos computadores e seus componentes no universo hardware.

### 3.1. Coprocessadores

Os coprocessadores têm como função retirar a sobrecarga da CPU ao realizar uma funcionalidade específica que seria da CPU — uma ideia de delegação e subdivisão de funções, mas com um objetivo específico.

Um coprocessador gráfico é uma unidade lógica dedicada a assumir a pesada carga de trabalho da renderização visual. Em arquiteturas futuras, em vez da CPU principal calcular e enviar cada pixel individualmente para o monitor, ela enviará apenas comandos de alto nível (ex.: "mova o personagem para X e Y"). O hardware do coprocessador traduz essas instruções em sinais elétricos (VGA) de forma autônoma e paralela.

### 3.2. Memórias

De acordo com os princípios descritos por Patterson e Hennessy em *Computer Organization and Design*, o projeto eficiente de um *datapath* depende fortemente da organização da memória para evitar gargalos de latência e conflitos de acesso. A arquitetura utiliza a memória interna da FPGA (blocos M10K, operando com a velocidade e o determinismo de memórias SRAM) dividida em duas funções estritas:

* **RAM Dual-Port:** Empregada sob o mesmo princípio de um banco de registradores (*register file*) de um processador *pipelined*, esta memória dinâmica armazena os índices do mapa e possui portas de acesso independentes. A porta de leitura opera continuamente para alimentar o fluxo de vídeo (varredura), enquanto a porta de escrita recebe comandos de alteração do usuário. Essa estrutura *dual-port* resolve o que a literatura chama de *structural hazard* (conflito estrutural), garantindo que a edição do cenário ocorra em tempo real sem causar travamentos ou corrupção no sinal contínuo enviado ao monitor.
* **ROM One-Port:** Conceitualmente descrita na arquitetura de computadores como uma tabela-verdade (*look-up table*) gigante e imutável, a ROM armazena a estética dos blocos (texturas). Ela não guarda estado dinâmico; seu papel é atuar como um decodificador fixo definido em tempo de síntese.
* **O fluxo de dados (encadeamento):** O fluxo assemelha-se ao ciclo de busca de instruções de uma CPU. Durante a varredura de tela, a RAM recebe a coordenada atual e fornece um índice numérico. Esse índice atua imediatamente como endereço de acesso na ROM, que por sua vez entrega o dado final (o arranjo de pixels daquele bloco) para o estágio de composição do *pipeline* visual.

### 3.3. Renderização On-the-Fly vs. Framebuffer

A abordagem tradicional de vídeo em computadores modernos utiliza um *framebuffer* — uma memória RAM massiva que armazena a cor de todos os pixels da tela simultaneamente. Contudo, a adoção de um *framebuffer* interno em uma FPGA esbarra em restrições severas de arquitetura de hardware:

* **Gargalo de largura de banda (*memory bandwidth*):** Para atualizar e ler um *framebuffer* completo a 640×480 pixels a 60 Hz, o sistema exigiria fluxos massivos de escrita e leitura simultâneas, criando dependências de dados severas e riscos de travamento no barramento (*data hazards*).
* **Granularidade dos blocos M10K:** A FPGA Cyclone V não possui um bloco único e contínuo de RAM como um computador pessoal, mas sim dezenas de pequenos blocos isolados chamados M10K. Unir esses blocos para formar um *framebuffer* contínuo exigiria uma malha complexa de multiplexação de endereços.
* **A solução (*on-the-fly*):** Optou-se pela renderização instantânea acoplada à varredura (*beam racing*). O sistema não armazena a tela inteira. A arquitetura de *datapath* calcula a cor de cada pixel de forma combinacional e síncrona, com acesso determinístico de ciclo fixo, alinhando-se à frequência de 25 MHz do controlador VGA e eliminando qualquer risco de *stall* no fluxo de vídeo.

---

## 4. Arquitetura e Datapath

A arquitetura do coprocessador foi estruturada em torno de um núcleo centralizador (`top_video.v`), que interliga subsistemas independentes de temporização, controle de estado e motores gráficos através de um *datapath* síncrono.

### 4.1. Gerenciamento de Clock e Base de Tempo

O sistema opera a partir de um sinal de clock de 50 MHz (`CLOCK_50`) fornecido pela placa DE1-SoC. Através do módulo `clock_divider`, emprega-se um flip-flop do tipo T (*toggle*) para realizar a divisão exata por 2, gerando um sinal de 25 MHz (`clk25`).

* Esta frequência é o parâmetro crítico que alimenta o controlador de vídeo (`vga_driver`), responsável por simular o comportamento de varredura de um monitor de 640×480 pixels a aproximadamente 60 Hz.
* O driver mapeia contadores horizontais (`h_counter`) e verticais (`v_counter`) para gerar os pulsos de sincronismo (`VGA_HS` e `VGA_VS`) e fornecer continuamente as coordenadas físicas ativas (`next_x` e `next_y`). A temporização segue o padrão VGA 640×480@60Hz: 800 ciclos de pixel por linha (640 ativos + 16 *front porch* + 96 pulso + 48 *back porch*) e 525 linhas por quadro (480 ativas + 10 + 2 + 33), resultando em ≈25,175 MHz teóricos — os 25 MHz obtidos por divisão simples ficam dentro da tolerância aceita pela maioria dos monitores.
* Para atender à exigência de uma resolução lógica da cena de 320×240 pixels com duplicação de pixels na saída (ampliação visual por um fator 2×2), essas coordenadas sofrem um deslocamento lógico de bits à direita (`>> 1`, i.e. `next_x[9:1]`/`next_y[9:1]`). Essa técnica dimensiona a área de atuação dos motores gráficos de forma eficiente antes de atingirem o estágio final de saída.

### 4.2. Datapath Multiplexado e Roteamento de Comandos (`mef_demonstracao.v`)

Como a placa possui uma quantidade limitada de botões físicos (`KEY`) e chaves de dados (`SW`), a arquitetura implementa uma **interface de comando** (`mef_demonstracao`). Este módulo atua como um demultiplexador inteligente de sinais de controle, com as chaves seletoras `SW[9:8]` atuando diretamente como bits de seleção do barramento:

| `SW[9:8]` | Modo | Sinais liberados para o *datapath* |
|:---:|---|---|
| `00` | Ocioso (IDLE) | Todas as saídas de controle em repouso (`0`) |
| `01` | Background | `bg_d` (dados de tile/cor), `bg_wr_addr` (cursor de edição), *scroll* via `KEY[2]`/`KEY[3]` |
| `10` | Polígonos | Coordenadas do retângulo/triângulo ativo, cor via `SW[5:0]` + `KEY[1]` |
| `11` | Sprites | `spr_d[3:0]` (direção contínua), `spr_d[6:4]` (seleção de personagem) |

Por ser puramente combinacional, este bloco garante latência zero no repasse dos comandos do usuário e resolve o *structural hazard* das entradas físicas, impedindo que um único botão mova o cenário e o personagem simultaneamente. Vale registrar que, por não possuir elemento de memória (não há registrador de estado interno — o "estado atual" é uma função direta de `SW[9:8]`), este bloco funciona como um decodificador de modo combinacional, e não como uma FSM registrada no sentido clássico; essa escolha foi deliberada para dar resposta instantânea e determinística ao alternar contextos usando chaves físicas (não pulsadas) da DE1-SoC, servindo de ponte direta para a futura FSM sequencial que decodificará a ISA de 32 bits vinda do driver.

### 4.3. Topologia de Interconexão e Memórias Independentes (`top_video.v`)

No módulo de topo (`top_video.v`), as instâncias de hardware isolam completamente o acesso aos recursos gráficos para assegurar determinismo de ciclo:

* **Módulos de interface de ROM:** Os blocos `motor_tile` e `rom_sprites_inst` encapsulam as instâncias de *megafunctions* geradas via IP Catalog (configuradas no modo ROM 1-PORT), utilizando blocos físicos M10K dedicados da FPGA Cyclone V.
* **Isolamento de barramentos:** Os sinais de endereço e dados do background (`bg_rom_addr`, `bg_rom_data`) e dos sprites (`spr_rom_addr`, `spr_rom_data`) trafegam por vias físicas totalmente independentes até convergirem exclusivamente no estágio final do compositor. Isso elimina qualquer gargalo de contenção de barramento entre as camadas visuais.

### 4.4. O Datapath das Memórias: a Mecânica entre RAM e ROM

O motor de fundo (*background*) reside na interação síncrona entre duas estruturas de memória distintas alocadas nos blocos M10K da FPGA:

* **RAM Dual-Port (Tilemap):** Armazena o mapa lógico do cenário — um *tilemap* de 40×30 posições. O endereço linear é calculado por `tilemap_addr = tile_row × 40 + tile_col`, cobrindo as 1.200 posições do mapa em um barramento de **11 bits**. A porta de leitura é vinculada ao feixe de varredura do monitor e opera com **1 ciclo de latência** (saída registrada do `altsyncram`); a porta de escrita permite alterar o tile associado a cada posição em tempo real, sem congelar ou corromper a imagem exibida.
* **ROM (armazenamento de tiles):** O dado de saída da RAM (`tile_id`, 8 bits) é concatenado com a posição interna do pixel dentro do bloco para formar o endereço de leitura da ROM: `rom_addr = {tile_id, pixel_y[2:0], pixel_x[2:0]}`, um barramento de **14 bits** que endereça 16.384 posições — ou seja, até **256 padrões gráficos distintos de 8×8 pixels** (64 pixels cada). Assim como a RAM, a ROM é configurada com saída registrada (`outdata_reg_a = "CLOCK0"`), adicionando mais **1 ciclo de latência**.
* **Comunicação:** O elo entre as duas memórias é puramente estrutural no *datapath* — o índice de tile fornecido pela RAM é injetado diretamente como endereço de entrada da ROM, que devolve o dado de cor bruto para o compositor. A latência total do caminho **coordenada → RAM → ROM** é, portanto, de **2 ciclos de `clk25`** — valor que a <!-- CORRIGIDO: 3.5 → 4.5 -->seção 4.5 usa como referência para dimensionar o *pipeline* de compensação.

### 4.5. Pipeline de Sincronização e o Compositor

Como os blocos M10K exigem ciclos de clock físicos para efetuar o acesso síncrono, a cadeia de leitura do cenário (coordenada → RAM → ROM) introduz uma latência inerente de **2 ciclos**, enquanto os motores de polígonos e sprites realizam cálculos predominantemente combinacionais e imediatos. Sem compensação, isso geraria desalinhamento visual (bordas tracejadas ou "fantasmas") entre as camadas. A arquitetura resolve isso com uma contabilidade de ciclos específica para cada camada:

* **Polígonos** não possuem nenhuma memória no seu caminho de dados — o resultado da função de aresta é combinacional e imediato (0 ciclos intrínsecos). Para alcançar a latência de 2 ciclos do fundo, o sinal passa por **dois registradores em série** (`poly_ativo_1 → poly_ativo_2`, `poly_color_1 → poly_color_2`).
* **Sprites** já herdam **1 ciclo intrínseco** da leitura registrada da ROM de sprites (mesma configuração `outdata_reg_a = "CLOCK0"`). Por isso, precisam de apenas **1 registrador adicional** (`spr_ativo_atrasado`, `spr_color_atrasado`) para fechar os mesmos 2 ciclos do fundo.

Os três sinais — agora sincronizados no mesmo instante de tempo lógico — ingressam no compositor, que arbitra a prioridade visual de cada camada em tempo real. O sistema aplica a regra de transparência antes da seleção do pixel final, na qual o índice de cor `0` atua de modo reservado como transparente para sprites e polígonos. O pixel vencedor é traduzido diretamente para o formato de saída (mapeamento fixo RGB332 — 3 bits de vermelho, 3 de verde, 2 de azul, decisão adotada em aula para evitar a latência adicional de uma RAM de paleta programável) e enviado aos pinos analógicos do DAC VGA.

### 4.6. Escalabilidade e Preparação para o Coprocessamento (Fase 2)

O núcleo gráfico atual foi projetado visando a transição direta para uma arquitetura completa de coprocessamento. Analisando os requisitos futuros do sistema, a base atual já atende às demandas mais críticas de hardware:

* **Unidade de desenho e VGA contínuo:** os motores de renderização (background, sprites e polígonos) e o controlador VGA já operam de forma autônoma, independentemente do modo selecionado em `SW[9:8]`.
* **Memórias internas:** o armazenamento de atributos e texturas já está devidamente roteado e encapsulado nos blocos M10K.
* **Escalonamento:** como o *datapath* visual já está estabilizado e isolado através do `mef_demonstracao`, a substituição das chaves físicas da placa (SW e KEY) por uma futura Unidade de Controle (UC) e uma Unidade Lógica e Aritmética (ULA) ocorrerá de forma modular. O sistema está pronto para receber um Registrador de Instruções (IR) de 32 bits, bastando conectar as saídas da futura UC diretamente nas entradas de dados que hoje são alimentadas pela placa.

---

## 5. Detalhamento dos Motores Gráficos

O núcleo gráfico é composto por três motores independentes, que formam a Unidade de Desenho, operando em paralelo de forma que as saídas são unificadas pelo compositor.

### 5.1. Motor de Background e Gerenciamento de Rolagem (*Scroll*)

O subsistema de fundo transforma as coordenadas lógicas da tela em uma malha contínua de blocos (*tiles*) de 8×8 pixels, implementado em `motor_background.v` e `motor_tilemap.v`.

* **Conversão e resolução lógica:** o sistema descarta o bit menos significativo das coordenadas físicas do VGA (`next_x[9:1]`, `next_y[9:1]`), convertendo a resolução de 640×480 para uma área de processamento lógica de 320×240 pixels.
* **Matemática de rolagem e *wrap-around*:** as coordenadas lógicas são somadas aos deslocamentos de câmera (`scroll_x`, `scroll_y`). Para simular um mundo contínuo, o hardware aplica verificações condicionais: se a posição somada ultrapassar os limites da tela (320 no eixo X, 240 no eixo Y), o sistema reinicia o ciclo subtraindo o valor limite, garantindo paginação contínua sem estouro de barramento.
* **Endereçamento linear do tilemap:** a partir da posição com *scroll*, o motor isola os 3 bits menos significativos para identificar a posição interna do pixel dentro do tile (`pixel_x`, `pixel_y`), enquanto os bits restantes formam a linha e a coluna do mapa (ver fórmula e larguras de barramento na <!-- CORRIGIDO: 3.4 → 4.4 -->seção 4.4).

### 5.2. Motor de Sprites e Banco de Atributos Dinâmicos (`motor_sprites.v`)

O subsistema de sprites gerencia entidades gráficas móveis e independentes de 16×16 pixels, suportando até **32 instâncias simultâneas** armazenadas em uma RAM interna de atributos (`sprite_ram`), com um registrador de 32 bits por sprite: 1 bit de habilitação, 2 bits de espelhamento (X/Y), 8 bits de padrão gráfico, 8 bits de posição Y e 9 bits de posição X.

* **Varredura e máscara de cobertura (*hit mask*):** a cada ciclo de pixel, um bloco `generate` testa simultaneamente se as coordenadas lógicas atuais estão dentro da área 16×16 de cada sprite habilitado.
* **Resolução de prioridade reversa:** para resolver colisões espaciais entre múltiplos sprites, um laço combinacional varre a matriz de acertos em ordem decrescente de índice:

  ```
  for i in 31 downto 0:
      if hit(sprite[i], x, y) and enabled(sprite[i]):
          winner = sprite[i]   // sobrescreve; ao final, o menor índice prevalece
  ```

  Como os índices menores são avaliados por último no laço, eles sobrescrevem os resultados anteriores, garantindo que o **sprite 0** (reservado ao jogador) domine obrigatoriamente sobre os demais em caso de sobreposição.
* **Espelhamento e mapeamento de quadrantes:** o motor decodifica as *flags* de espelhamento (`flip_x`, `flip_y`), invertendo o vetor de deslocamento local (`15 − raw_dx`) e calculando o subquadrante correspondente para mapear a textura correta na ROM dedicada de sprites.

### 5.3. Rasterizador Procedural de Polígonos (`rasterizador_poligonos.v`)

O rasterizador desenha formas geométricas preenchidas (retângulos e triângulos) diretamente em hardware, eliminando a necessidade de texturas estáticas em memória para formas básicas.

* **Retângulos:** renderizados por lógica combinacional direta, comparando se a coordenada atual do pixel está entre os limites dos cantos superior-esquerdo e inferior-direito.
* **Triângulos e funções de aresta (*edge functions*):** o módulo implementa o produto vetorial entre arestas (funções $e_{01}$, $e_{12}$, $e_{20}$) para determinar de que lado de cada aresta o pixel testado se encontra; o pixel é preenchido apenas quando está do lado interno das três.
* **Prevenção de *underflow* (aritmética com sinal):** as coordenadas de entrada são inteiros sem sinal de 8/9 bits (0 a 255/511). Uma subtração entre duas dessas coordenadas pode variar de −511 a +511, faixa que exige **11 bits em complemento de dois** (10 bits de magnitude + 1 de sinal) para representação sem perda. O *datapath* estende preventivamente as entradas para registradores assinados de 11 bits antes de calcular as diferenças, e o produto dessas diferenças (usado nas funções de aresta) é acumulado em barramentos de até 24 bits — evitando falhas silenciosas de rasterização por *overflow*/*underflow*.

### 5.4. Pipeline de Atraso e o Compositor (`compositor.v`)

A contabilidade completa de ciclos entre os três motores está detalhada na <!-- CORRIGIDO: 3.5 → 4.5 -->seção 4.5 — em resumo, o *pipeline* de compensação garante que sprite, polígono e background cheguem ao compositor no mesmo instante lógico, apesar de terem latências intrínsecas diferentes (0, 1 e 2 ciclos, respectivamente, antes da compensação).

O compositor avalia os sinais já sincronizados e aplica a regra de transparência estrita (índice de cor `0` descartado) obedecendo à hierarquia oficial de prioridade visual:

$$\text{Sprite} > \text{Polígono} > \text{Background}$$

O pixel vencedor é mapeado diretamente para o formato de saída e enviado aos pinos analógicos do DAC VGA.

---

## 6. Levantamento de Requisitos e Status de Atendimento

Os requisitos abaixo seguem a numeração original do enunciado (Problema #1, seção 4). Cada item foi conferido diretamente contra o RTL do repositório. Legenda:

- ✅ Atendido
- ⚠️ Parcialmente atendido (justificado)
- ❌ Não atendido (justificado)

### 6.1 Entradas e saídas

- [x] ✅ Saída de vídeo em 640×480 pixels, ~60 Hz, via interface VGA da DE1-SoC
- [x] ✅ Resolução lógica da cena de 320×240 pixels, com duplicação de pixels na saída (fator 2×2)
- [x] ✅ Botões, chaves e LEDs usados exclusivamente para demonstração do núcleo, sem substituir a futura interface MMIO — sinais de `SW`/`KEY` isolados do restante do *datapath* em `top_video.v`

### 6.2 Núcleo do coprocessador gráfico — Verilog

- [x] ✅ Núcleo inteiramente descrito em Verilog
- [x] ✅ Arquitetura modular, com separação clara entre controle (`mef_demonstracao`), *datapath*, memórias e motores gráficos (`motor_background`, `motor_sprites`, `rasterizador_poligonos`), e saída de vídeo (`vga_driver`)
- [x] ✅ Registradores e memórias com estratégia definida de reinicialização/inicialização — reset síncrono (`posedge clk or posedge reset`) em todos os módulos sequenciais; ROMs inicializadas via arquivo `.mif`
- [x] ✅ **Saída sem instabilidade visual, perda de sincronismo ou pixels indefinidos** — observado de forma estável na demonstração em bancada <!-- PENDENTE DE CONFIRMAÇÃO: ver observação no final do documento sobre fechamento de timing (.sdc) -->

### 6.3 Motor de background

- [x] ✅ Camada de background baseada em *tilemap* de 40×30 entradas
- [x] ✅ Tiles de 8×8 pixels em memória interna, com 256 padrões disponíveis (ROM de 14 bits de endereço = 16.384 posições = 256 × 64 pixels)
- [x] ✅ Alteração do tile associado a cada posição do *tilemap*, em tempo real
- [x] ✅ Deslocamento horizontal e vertical da camada, com tratamento de repetição (*wrap-around* por subtração do limite)
- [x] ✅ Geração de índice de cor válido para cada pixel da região visível, sem interromper o fluxo de vídeo

### 6.4 Motor de sprites

- [x] ✅ Memória de atributos para no mínimo 32 sprites
- [x] ✅ Sprites de 16×16 pixels, endereçados por quadrante na ROM de padrões de 8×8
- [ ] ⚠️ **Atributos mínimos por sprite** — o registrador de 32 bits por sprite hoje contém apenas: habilitação, espelhamento X, espelhamento Y, índice do padrão gráfico (8 bits), posição Y (8 bits) e posição X (9 bits).
  - ⚠️ **Prioridade por sprite**: hoje a prioridade é *implícita* pelo índice fixo no array (sprite 0 sempre vence), não é um atributo programável independente da posição na memória.
  - ❌ **Seleção de paleta por sprite**: <!-- ADICIONADO --> não se aplica, já que não há paleta programável no sistema (ver 6.6).
- [x] ✅ Prioridade entre sprites que ocupam o mesmo pixel documentada e determinística (varredura decrescente de índice, sprite de menor índice vence)

### 6.5 Rasterizador de polígonos

- [x] ✅ Desenho de triângulos e retângulos preenchidos
- [x] ✅ Aritmética inteira (extensão de sinal para 11 bits, evitando *underflow* nas funções de aresta)

### 6.6 Compositor, paleta e saída VGA

- [x] ✅ Composição, a cada pixel, das contribuições de background, polígonos e sprites
- [x] ✅ No mínimo 3 níveis de prioridade entre as camadas, com regra documentada (Sprite > Polígono > Background)
- [x] ✅ Transparência aplicada antes da seleção do pixel final (índice de cor `0` descartado em sprites e polígonos)
- [ ] ❌ **Paleta programável de 256 entradas RGB** — não implementada. O índice de 8 bits é convertido para RGB por mapeamento fixo (RGB332: 3 bits R, 3 bits G, 2 bits B), decisão adotada por orientação do professor em aula para evitar a latência de leitura de uma RAM de paleta adicional. Tecnicamente, isso significa que o mapeamento cor↔índice **não é reprogramável em tempo de execução**, como o termo "paleta programável" implica. *Justificativa registrada oficialmente na <!-- CORRIGIDO: 3.5 → 4.5 -->seção 4.5 da Arquitetura e na seção de Funcionalidades Não Atendidas.*

---

## 7. Verificação Funcional (Demonstração em Bancada)
 
Como descrito na seção 6, a verificação deste primeiro problema foi conduzida por **demonstração dirigida em hardware**, usando as chaves (`SW`) e botões (`KEY`) da placa como estímulo de teste, e não por testbenches automatizados em simulação. O modo ativo é sempre selecionado por `SW[9:8]`, roteado combinacionalmente pelo módulo `mef_demonstracao.v`. Os registradores de cada camada (posição dos polígonos, conteúdo do *tilemap*, *scroll*) **não são reiniciados ao trocar de modo** — só voltam ao padrão com `KEY[0]` (reset) — o que permite configurar uma camada, mudar de modo, e ainda ver o resultado anterior compondo com as demais camadas.
 
### 7.1 Modo `00` — Ocioso (IDLE)
 
Todas as saídas de controle ficam em repouso. Nenhuma chave ou botão tem efeito sobre o conteúdo das camadas; usado para verificar a saída de vídeo estável logo após o reset (`KEY[0]`).
 
### 7.2 Modo `01` — Background
 
| Controle | Função | Faixa / passo |
|---|---|---|
| `SW[7] = 0` | Ativa o **modo edição** de tile | — |
| `SW[7] = 1` | Ativa o **modo scroll** | — |
| `SW[6:0]` (só em modo edição) | Índice do tile a gravar na posição do cursor | `0`–`127` — o bit 7 de `SW` precisa ficar em `0` para a escrita ser habilitada (`real_bg_wr_en`), então metade da ROM de tiles (índices 128–255) não é alcançável por este controle de demonstração, só por uma futura escrita via MMIO |
| `KEY[2]` (modo edição) | Avança o cursor de escrita no *tilemap* | `bg_wr_addr + 1` |
| `KEY[3]` (modo edição) | Retrocede o cursor de escrita | `bg_wr_addr − 1` |
| `KEY[1]` (modo edição) | Grava o tile indicado por `SW[6:0]` na posição atual do cursor | — |
| `SW[6] = 0` (modo scroll) | Seleciona rolagem no eixo X | — |
| `SW[6] = 1` (modo scroll) | Seleciona rolagem no eixo Y | — |
| `KEY[2]` / `KEY[3]` (modo scroll) | Incrementa / decrementa o deslocamento de câmera no eixo selecionado | ±2 pixels lógicos por pulso |
 
### 7.3 Modo `10` — Polígonos
 
| Controle | Função | Faixa / passo |
|---|---|---|
| `SW[7] = 0` | Seleciona o **retângulo** como forma ativa | — |
| `SW[7] = 1` | Seleciona o **triângulo** como forma ativa | — |
| `SW[6] = 0` | Movimento no eixo X | — |
| `SW[6] = 1` | Movimento no eixo Y | — |
| `KEY[2]` | Move a forma ativa no sentido positivo do eixo selecionado | +5 pixels lógicos por pulso |
| `KEY[3]` | Move a forma ativa no sentido negativo do eixo selecionado | −5 pixels lógicos por pulso |
| `SW[5:0]` | Valor de cor a gravar na forma ativa | `0`–`63` — os 2 bits mais significativos do índice de cor são forçados a `0` na escrita (`{2'b00, SW[5:0]}`), então apenas 64 dos 256 índices de cor são alcançáveis por este controle |
| `KEY[1]` | Grava o valor de `SW[5:0]` como cor da forma ativa | — |
 
*Retângulo padrão após reset:* 80×40 pixels lógicos, cor índice 5, posição inicial (50, 50).
*Triângulo padrão após reset:* base 80 / altura 60 pixels lógicos, cor índice 15, posição inicial (200, 100).
 
### 7.4 Modo `11` — Sprites
 
Nesta atualização, o `controlador_sprite.v` passou a gerenciar **4 sprites controláveis** (`id_alvo` 0–3) em paralelo, cada um com posição, personagem e espelhamento próprios guardados internamente no controlador. `SW[5:4]` escolhe qual desses 4 sprites recebe os comandos no momento — os outros três permanecem parados na última posição configurada, o que permite posicionar vários sprites em pontos diferentes da tela ao longo da demonstração.
 
| Controle | Função em modo movimento (`SW[7] = 0`) | Função em modo espelhamento (`SW[7] = 1`) |
|---|---|---|
| `SW[3]` | Move o sprite selecionado para **cima** | Liga o espelhamento vertical (`flip_y = 1`) |
| `SW[2]` | Move o sprite selecionado para **baixo** | Desliga o espelhamento vertical (`flip_y = 0`) |
| `SW[1]` | Move o sprite selecionado para **esquerda** | Liga o espelhamento horizontal (`flip_x = 1`) |
| `SW[0]` | Move o sprite selecionado para **direita** | Desliga o espelhamento horizontal (`flip_x = 0`) |
 
| Controle | Função | Faixa / passo |
|---|---|---|
| `SW[5:4]` | Seleciona qual dos 4 sprites (`id_alvo`) recebe os comandos de `SW[3:0]` | `0`–`3` |
| `SW[7]` | Alterna entre modo movimento (`0`) e modo espelhamento (`1`) para o sprite selecionado — reaproveita os mesmos bits `SW[3:0]`, não é uma trava independente | — |
| `SW[6]` | Avança o personagem do sprite selecionado, **por borda de subida** (é preciso abaixar e levantar a chave a cada passo, não basta deixá-la levantada) | `0`–`6` (7 personagens), volta a `0` após `6` |
 
Notas de comportamento, verificadas diretamente no `controlador_sprite.v` e no `motor_sprites.v`:
- O movimento/espelhamento é processado a ~20 Hz (`SPEED_LIMIT = 1.250.000` ciclos de `clk25`, um passo a cada 50 ms); cada passo de movimento é de **1 pixel lógico**.
- A troca de personagem (`SW[6]`) tem prioridade sobre o movimento/espelhamento quando os dois acontecem no mesmo instante.
- A posição de cada sprite é limitada por *hardware* aos limites da tela lógica menos o tamanho do sprite: `X ∈ [0, 304]`, `Y ∈ [0, 224]` (320×240 − 16×16).
- Ao resetar (`KEY[0]`), os 4 sprites já nascem posicionados e habilitados: sprite 0 (jogador, personagem 0) em (100, 100); sprites 1–3 (personagens 1, 2 e 4, representando inimigos parados) em (200, 50), (50, 150) e (250, 180), respectivamente — os valores de reset em `motor_sprites.v` e `controlador_sprite.v` foram conferidos e são consistentes entre si.
- A prioridade de sobreposição entre os 4 sprites segue a mesma regra da seção 5.2 (menor índice vence): sprite 0 > sprite 1 > sprite 2 > sprite 3.
- Fora do modo `11`, os sprites ficam parados (`spr_d` zerado pela MEF) nas últimas posições configuradas — por isso o compositor consegue mostrar, no fechamento da demonstração, os sprites sobrepostos ao *background* editado e aos polígonos movidos nos modos anteriores, sem precisar voltar a eles.
