# SENECA REBORN — versão de navegador

ARPG cooperativo de fantasia sombria para até 5 jogadores, direto no navegador, sem instalar nada.

**Jogar:** https://dmebikevca-max.github.io/seneca-reborn/

- Funciona no Chrome, Edge ou Firefox de computador (teclado e mouse).
- Na primeira vez o navegador baixa cerca de 130 MB; depois fica guardado e só baixa o que mudou.
- Para jogar com amigos: crie uma sala, clique em **Copiar convite** e mande o link. Quem abrir o link entra direto na sala.

Este repositório guarda só o jogo pronto (página, motor e pacote do jogo) e o servidor online:

- `index.*` — a página do jogo (GitHub Pages).
- `servidor/` — o servidor dedicado (Linux) que roda na nuvem; `versao.json` diz qual versão está publicada.
- `espaco/` — os arquivos do servidor no Hugging Face Spaces (Docker): baixa o servidor daqui e se atualiza sozinho.
