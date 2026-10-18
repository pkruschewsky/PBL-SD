# Tiles do background

- **0 a 120**: pedacos da cena inicial (ceu, nuvens, montanhas, cidade, rua) - veja os numeros em `catalogo_tiles.png`
- **121 a 159**: livres (pretos)
- **160 a 223**: tiles avulsos, sempre nos mesmos numeros (**224 a 255** livres):

| Tile | Conteudo |
|---|---|
| 160 | letra '0' |
| 161 | letra '1' |
| 162 | letra '2' |
| 163 | letra '3' |
| 164 | letra '4' |
| 165 | letra '5' |
| 166 | letra '6' |
| 167 | letra '7' |
| 168 | letra '8' |
| 169 | letra '9' |
| 170 | letra 'A' |
| 171 | letra 'B' |
| 172 | letra 'C' |
| 173 | letra 'D' |
| 174 | letra 'E' |
| 175 | letra 'F' |
| 176 | letra 'G' |
| 177 | letra 'H' |
| 178 | letra 'I' |
| 179 | letra 'J' |
| 180 | letra 'K' |
| 181 | letra 'L' |
| 182 | letra 'M' |
| 183 | letra 'N' |
| 184 | letra 'O' |
| 185 | letra 'P' |
| 186 | letra 'Q' |
| 187 | letra 'R' |
| 188 | letra 'S' |
| 189 | letra 'T' |
| 190 | letra 'U' |
| 191 | letra 'V' |
| 192 | letra 'W' |
| 193 | letra 'X' |
| 194 | letra 'Y' |
| 195 | letra 'Z' |
| 196 | letra ' ' |
| 197 | letra ':' |
| 198 | letra '!' |
| 199 | letra '-' |
| 200 | letra '.' |
| 201 | letra '?' |
| 208 | tijolo |
| 209 | pedra |
| 210 | grama |
| 211 | terra |
| 212 | agua (quadro A) |
| 213 | agua (quadro B) |
| 214 | caixa de madeira |
| 215 | metal |
| 216 | lava (quadro A) |
| 217 | lava (quadro B) |
| 218 | gelo |
| 219 | areia |
| 220 | janela acesa (parede cinza) |
| 221 | janela apagada (parede cinza) |
| 222 | preto |
| 223 | branco |

Texto: `tile = 160 + digito` para 0-9 e `tile = 170 + (letra - 'A')` para A-Z; espaco = 196.

Na cena, a janela acesa de parede cinza e o tile **75** e a apagada o **74** (iguais aos avulsos 220/221). Algumas posicoes (linha, coluna) com janela acesa: [(16, 37), (16, 38), (17, 35), (17, 38), (18, 0), (18, 1), (18, 2), (18, 35)]
