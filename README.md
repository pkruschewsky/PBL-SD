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

Este projeto teve como objetivo o desenvolvimento de um núcleo gráfico dedicado em hardware (FPGA), inspirado na arquitetura clássica de consoles de 16 bits. A solução foi projetada para sintetizar um sinal de vídeo VGA (640x480 a 60 Hz) através da orquestração de múltiplas camadas visuais simultâneas: um plano de fundo baseado em blocos (Tilemap), entidades móveis independentes (Sprites) e um rasterizador procedural de polígonos.

A implementação foi realizada inteiramente em linguagem Verilog, utilizando a plataforma DE1-SoC (Intel Cyclone V). Um aspecto central do projeto foi a adoção de uma arquitetura de renderização on-the-fly — descartando a utilização de um framebuffer estático completo para otimização de recursos. Essa decisão exigiu o gerenciamento preciso de latências, o uso de memórias de forma síncrona/assíncrona e a orquestração de um Datapath dedicado. 

O sistema final foi feito com o propósito de preparar o núcleo de hardware para, em etapas posteriores, atuar de forma autônoma sob o comando de um driver em Assembly ARM e uma aplicação em linguagem C.

---
## 2. Fundamentação teórica

Para atender aos requisitos da construção do núcleo gráfico, foi necessário entender e pesquisar sobre a arquitetura dos computadores e seus componentes no universo hardware.

## 2.1. Coprocessadores

Os coprocessadores têm como função retirar a sobrecarga da CPU ao realizar uma funcionalidade específica que seria da CPU. Uma ideia de delegação e subdivisão de funções, mas com um objetivo específico.

Um coprocessador gráfico é uma unidade lógica dedicada a assumir a pesada carga de trabalho da renderização visual. Em arquiteturas futuras, em vez da CPU principal calcular e enviar cada pixel individualmente para o monitor, ela enviará apenas comandos de alto nível (ex: "mova o personagem para X e Y"). O hardware do coprocessador traduz essas instruções em sinais elétricos (VGA) de forma autônoma e paralela.

## 2.2. Memórias 

De acordo com os princípios descritos por Patterson e Hennessy em Computer Organization and Design, o projeto eficiente de um datapath depende fortemente da organização da memória para evitar gargalos de latência e conflitos de acesso. A arquitetura utiliza a memória interna da FPGA (blocos M10K, operando com a velocidade e o determinismo de memórias SRAM) dividida em duas funções estritas:

* *RAM Dual-Port:* Empregada sob o mesmo princípio de um Banco de Registradores (Register File) de um processador pipelined, esta memória dinâmica armazena os índices do mapa e possui portas de acesso independentes. A porta de leitura opera continuamente para alimentar o fluxo de vídeo (varredura), enquanto a porta de escrita recebe comandos de alteração do usuário. Essa estrutura Dual-Port resolve o que a literatura chama de Structural Hazard (Conflito Estrutural), garantindo que a edição do cenário ocorra em tempo real sem causar travamentos ou corrupção no sinal contínuo enviado ao monitor.
* *ROM One-Port:* Conceitualmente descrita na arquitetura de computadores como uma tabela-verdade (Look-Up Table) gigante e imutável, a ROM armazena a estética dos blocos (texturas). Ela não guarda estado dinâmico; seu papel é atuar como um decodificador fixo definido em tempo de síntese.
* *O Fluxo de Dados (Encadeamento):* O fluxo assemelha-se ao ciclo de busca de instruções de uma CPU. Durante a varredura de tela, a RAM recebe a coordenada atual e fornece um índice numérico. Esse índice atua imediatamente como endereço de acesso na ROM, que por sua vez entrega o dado final (o arranjo de pixels daquele bloco) para o estágio de composição do pipeline visual.

### 2.3. Renderização On-the-Fly vs. Framebuffer

A abordagem tradicional de vídeo em computadores modernos utiliza um Framebuffer — uma memória RAM massiva que armazena a cor de todos os pixels da tela simultaneamente. Contudo, a adoção de um Framebuffer interno em uma FPGA esbarra em restrições severas de arquitetura de hardware:
* *Gargalo de Largura de Banda (*Memory Bandwidth):* Para atualizar e ler um *Framebuffer completo a 640x480 pixels a 60 Hz, o sistema exigiria fluxos massivos de escrita e leitura simultâneas, criando dependências de dados severas e riscos de travamento no barramento (Data Hazards).
* *Granularidade dos Blocos M10K:* A FPGA Cyclone V não possui um bloco único e contínuo de RAM DRAM como um computador pessoal, mas sim dezenas de pequenos blocos isolados chamados M10K. Unir esses blocos para formar um Framebuffer contínuo exigiria uma malha complexa de multiplexação de endereços.
* *A Solução (*On-the-Fly):* Optou-se pela renderização instantânea acoplada à varredura (*beam racing). O sistema não armazena a tela inteira. A arquitetura de Datapath calcula a cor de cada pixel de forma puramente combinacional e síncrona, com acesso determinístico de estritamente 1 ciclo de clock, alinhando-se perfeitamente à frequência de 25 MHz do controlador VGA e eliminando qualquer risco de stall no fluxo de vídeo.

---
## 3. Arquitetura e Datapath

A arquitetura do coprocessador foi estruturada em torno de um núcleo centralizador (`top_video.v`), que interliga subsistemas independentes de temporização, controle de estado e motores gráficos através de um *Datapath* síncrono de alta performance.

### 3.1. Gerenciamento de Clock e Base de Tempo
O sistema opera a partir de um sinal de relógio primário de 50 MHz (`CLOCK_50`) fornecido pela placa DE1-SoC. Através do módulo `clock_divider`, emprega-se um flip-flop do tipo *toggle* para realizar a divisão exata por 2, gerando um sinal estável de **25 MHz** (`clk25`), frequência padrão necessária para alimentar o controlador VGA. O driver mapeia contadores horizontais (`h_counter`) e verticais (`v_counter`) para gerar os pulsos de sincronismo (`VGA_HS` e `VGA_VS`) e fornecer continuamente as coordenadas físicas ativas (`next_x` e `next_y`).

Para atender à exigência de uma resolução lógica de $320\times240$ pixels com ampliação visual de $2\times2$[cite: 1], essas coordenadas sofrem um deslocamento lógico de bits à direita (>> 1). Essa técnica dimensiona a área de atuação dos motores gráficos de forma eficiente antes de atingirem o estágio final de saída.


### 3.2. O Datapath das Memórias: A Mecânica entre RAM e ROM
O coração do motor de fundo (Background) reside na interação síncrona entre duas estruturas de memória distintas alocadas nos blocos M10K da FPGA. Para responder com precisão a questionamentos sobre o fluxo de dados e evitar ambiguidades de leitura e escrita, a arquitetura divide-se estritamente da seguinte forma:

* *RAM Dual-Port (Tilemap):* 
  Esta memória armazena o mapa lógico do cenário (uma matriz de $40\times30$ posições utilizando blocos de $8\times8$ pixels)[cite: 1]. Por ser uma memória Dual-Port, ela possui duas portas de acesso independentes operando no mesmo ciclo de clock:
  1. Porta de Leitura Contínua: Vinculada ao feixe de varredura do monitor, lê ininterruptamente o índice numérico do tile correspondente à coordenada atual da tela.
  2. Porta de Escrita Paralela: Permite que o sistema externo (ou os botões de controle) altere o conteúdo de um endereço específico da matriz em tempo real, gravando um novo índice de tile sem congelar ou corromper a imagem exibida.

* *ROM (Armazenamento de tiles):*
  A ROM armazena a matriz de pixels estáticos de cada padrão gráfico disponível. Ela é estritamente de leitura e não recebe nenhum comando de escrita ou alteração de dados durante a execução do jogo.

* *Comunicação:*
  O elo que une as duas memórias é puramente estrutural no datapath. O dado de saída (rom_data) fornecido pela *RAM* (que indica, por exemplo, o número do tile "3") é injetado diretamente como o *endereço de entrada* da *ROM*. A ROM processa esse endereço combinado com a posição interna do pixel e indica o dado de cor bruto. Esse dado vai direto para o Compositor.

### 3.3. Pipeline de Sincronização e O Compositor
Como os blocos M10K exigem ciclos de clock físicos para efeturar o acesso síncrono, a cadeia de leitura do cenário (Coordenada $\rightarrow$ RAM $\rightarrow$ ROM) introduz uma latência inerente de 2 ciclos. 

Em contrapartida, os motores de Polígonos e Sprites realizam cálculos predominantemente combinacionais e imediatos. Para impedir que os elementos gráficos fiquem "desalinhados" ou tracejados na tela, a arquitetura implementa um *Pipeline de Atraso* (registros de deslocamento temporal). 

Os sinais sincronizados ingressam no Compositor, que arbitra a prioridade visual de cada camada em tempo real, aplicando a regra de transparência onde o índice de cor 0 é ignorado[cite: 1]. O pixel vencedor é traduzido diretamente para o formato de saída e enviado aos pinos analógicos do DAC VGA.





### 3.4. Datapath Multiplexado e a Máquina de Estados (`mef_demonstracao.v`)
Como a placa possui uma quantidade limitada de botões físicos (`KEY`) e chaves de dados (`SW`), a arquitetura implementa um **Datapath Multiplexado** governado por uma Máquina de Estados Finitos de demonstração (`mef_demonstracao.v`).
* **Roteamento de Contexto:** As chaves seletoras `SW[9:8]` atuam como o seletor de modo do sistema:
  * `2'b00`: Estado Ocioso (IDLE), mantendo os barramentos em repouso.
  * `2'b01`: Modo **Background**, direcionando os botões para controlar o deslocamento (*scroll*) ou a edição pontual de tiles no mapa.
  * `2'b10`: Modo **Polígonos**, permitindo transladar ou alterar a cor do retângulo e do triângulo ativos.
  * `2'b11`: Modo **Sprites**, viabilizando o movimento, a troca de entidades e o espelhamento dinâmico.
* Esta abordagem resolve problemas de conflito de barramento (*Structural Hazards*), garantindo que os mesmos comandos físicos operem múltiplos subsistemas sem sobreposição de ações indesejadas.

### 3.3. Topologia de Interconexão e Memórias Independentes (`top_video.v`)
No módulo de topo (`top_video.v`), as instâncias de hardware isolam completamente o acesso aos recursos gráficos para assegurar determinismo de ciclo:
* **Módulos de Interface de ROM:** Os blocos `motor_tile` e `rom_sprites_inst` encapsulam as instâncias de *megafunctions* geradas via IP Catalog (`altsyncram` configuradas no modo ROM pura de 1 porta), utilizando blocos físicos M10K dedicados da FPGA Cyclone V.
* **Isolamento de Barramentos:** Os sinais de endereço e dados do Background (`bg_rom_addr`, `bg_rom_data`) e dos Sprites (`spr_rom_addr`, `spr_rom_data`) trafegam por vias físicas totalmente independentes até convergirem exclusivamente no estágio final do Compositor. Isso elimina qualquer gargalo de contenção de barramento entre as camadas visuais.
