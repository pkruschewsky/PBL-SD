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
