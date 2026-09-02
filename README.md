# PBL-SD
Coprocessador gráfico em FPGA - TEC499

# Coprocessador Gráfico VGA Multicamadas em FPGA

Este repositório contém a documentação e o código-fonte de um coprocessador gráfico desenvolvido em hardware para a placa FPGA DE1-SoC (Intel Cyclone V).

---

## 1. Manual do Sistema

Este manual destina-se a engenheiros de computação e desenvolvedores, fornecendo a documentação técnica necessária para compreender e utilizar o sistema.

### 1.1 Declaração do Problema e Requisitos

O problema central deste projeto consistiu no desenvolvimento de um coprocessador gráfico em hardware capaz de gerenciar e renderizar múltiplas camadas gráficas de forma simultânea. O objetivo do hardware é atuar como um acelerador dedicado, libertando o processador principal (CPU) do cálculo exaustivo de varredura de pixels. 

Para que a solução resolva o problema, o sistema foi projetado para atender aos seguintes requisitos, abrangendo as especificações explícitas do problema e as necessidades implícitas da arquitetura digital:

*   **Geração de Sinal de Vídeo (Explícito):** Sintetizar um sinal analógico VGA com resolução física de 640x480 pixels a uma taxa de atualização de 60 Hz, fornecendo os pulsos de sincronismo vertical e horizontal ao monitor.
*   **Múltiplas Camadas de Renderização (Explícito):** Instanciar e orquestrar três motores gráficos independentes: um cenário de fundo (*Background*), um gerador de formas geométricas (Rasterizador de Polígonos) e um controlador de entidades móveis (*Sprites*).
*   **Controle e Datapath Multiplexado (Explícito):** Integrar os periféricos da placa (chaves `SW` e botões `KEY`) através de uma Máquina de Estados Finitos (MEF), roteando os comandos do usuário para o motor gráfico correspondente sem sobreposição indesejada de ações.
*   **Sincronização e Resolução de Conflitos Visuais (Implícito):** Implementar um Compositor capaz de arbitrar qual camada gráfica deve ser exibida quando há sobreposição espacial (Prioridade: Sprite > Polígono > Background). Adicionalmente, compensar a latência de leitura das memórias *Dual-Port* através de um *pipeline* de atraso temporal para alinhar a saída dos pixels.
*   **Gerenciamento Eficiente de Memória (Implícito):** Otimizar o uso de blocos BRAM internos da FPGA. Para o cenário, adotar a arquitetura de *Tilemaps* vinculada a uma ROM compartilhada de texturas em vez de *framebuffers* completos. Para os sprites, implementar uma RAM de atributos dinâmica.

### 1.2 Arquitetura da Solução Proposta

![Visão de Alto Nível do Coprocessador](diagrama.png)

A solução resolve o problema da renderização simultânea adotando uma arquitetura paralela de processamento de vídeo, orquestrada dentro do módulo principal `top_video.v` (instanciado no topo da placa `DE1_SOC_golden_top`). O sistema é dividido conceitualmente em três grandes eixos: Controle (Datapath), Geração de Coordenadas e Motores de Renderização.

**Fluxo de Controle e Dados:**
1. **Entradas e Roteamento (MEF):** Os controles físicos do usuário (`KEY[3:0]` e `SW[9:0]`) alimentam a Máquina de Estados Finitos (`mef_demonstracao`). A MEF atua como um multiplexador inteligente: ela lê os bits seletores de estado (`SW[9:8]`) e direciona os sinais dos botões (que funcionam como "direcionais" e "confirmar") e das chaves de dados apenas para o motor gráfico correspondente (Background, Polígonos ou Sprites). Isso resolve o problema de sobreposição de comandos, permitindo que a mesma interface física controle múltiplas camadas de forma independente.
2. **Base de Tempo e Coordenadas:** O módulo `clock_divider` reduz o relógio da placa de 50 MHz para 25 MHz, alimentando o `vga_driver`. O driver varre a tela e fornece as coordenadas físicas atuais (`next_x` e `next_y`) de 640x480 pixels. Para otimizar o processamento e a memória, essas coordenadas sofrem um deslocamento de bits lógico (`>> 1`), transformando a área de processamento interno dos motores gráficos em uma resolução lógica de 320x240 pixels (onde cada pixel computado é duplicado visualmente num bloco 2x2 na tela).
3. **Renderização Paralela:** As coordenadas lógicas alimentam simultaneamente os três motores de vídeo (`motor_background`, `motor_sprites` e `rasterizador_poligonos`). Cada bloco calcula de forma isolada qual deve ser a cor daquele pixel exato na sua respectiva camada.
4. **Sincronização (Pipeline):** Como o motor de cenário exige consultas encadeadas em memória (ler o Tilemap na RAM e depois a textura na ROM), ele possui um atraso inerente de 2 ciclos de *clock*. Para evitar que os sprites e polígonos fiquem "desalinhados" na tela em relação ao fundo, seus sinais passam por registradores de atraso (*Pipeline de Alinhamento*).
5. **Composição e Saída:** Os três sinais, agora perfeitamente sincronizados, entram no `compositor`. Ele aplica a regra matemática de sobreposição (Sprite > Polígono > Fundo), tratando o índice de cor `0` como transparente. O pixel vencedor é convertido diretamente para um empacotamento RGB de 8 bits (RRRGGGBB) e enviado aos pinos VGA analógicos da placa.
