# Servidor online do SENECA REBORN (Render, plano grátis).
# O contêiner baixa o servidor do repositório do GitHub e se atualiza sozinho a cada versão publicada.
FROM ubuntu:24.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends nginx curl ca-certificates jq procps postgresql-client \
    && rm -rf /var/lib/apt/lists/*

RUN (userdel -r ubuntu 2>/dev/null || true) && useradd -m -u 1000 jogo
WORKDIR /home/jogo/app
COPY --chown=jogo nginx.conf iniciar.sh pagina.html /home/jogo/app/
RUN chmod +x /home/jogo/app/iniciar.sh
USER jogo
ENV HOME=/home/jogo
EXPOSE 10000
CMD ["/home/jogo/app/iniciar.sh"]
