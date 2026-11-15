#!/bin/bash
# Liga o servidor do SENECA REBORN e o mantém na versão mais nova publicada no GitHub.
#  - baixa o servidor (binário + pacote) de BASE_SERVIDOR
#  - só troca de versão com o servidor vazio (ninguém jogando)
#  - o progresso fica com os jogadores (cópia assinada com SEGREDO_SAVES), porque o disco do
#    plano grátis é apagado quando o servidor dorme
set -u
BASE="${BASE_SERVIDOR:-https://raw.githubusercontent.com/dmebikevca-max/seneca-reborn/main/servidor}"
PORTA="${PORT:-10000}"
RAIZ="${RAIZ:-$HOME}"
APP="$RAIZ/app"
DIR="$RAIZ/servidor"
DADOS="$RAIZ/dados"
STATUS=/tmp/seneca_status.json
SAIR=/tmp/seneca_sair
DB="${DATABASE_URL:-}"
ENCERRANDO=0
mkdir -p "$DIR" "$DADOS"
cd "$APP" || exit 1
echo '{"estado": "iniciando"}' > "$STATUS"
# ------------------------------------------------------------------ banco de dados (Neon)
# O disco do plano grátis é apagado quando o servidor dorme. Com DATABASE_URL, as contas
# (pasta contas/) e os usuários (pasta usuarios/) são espelhados numa tabela do Postgres:
# baixados ao ligar e enviados a cada 20 s e ao desligar.
sincronizar_baixar() {
	[ -z "$DB" ] && return 0
	psql "$DB" -q -v ON_ERROR_STOP=1 -c "create table if not exists arquivos (caminho text primary key, conteudo text not null, atualizado timestamptz not null default now())" || return 1
	psql "$DB" -At -F '|' -v ON_ERROR_STOP=1 -c "select caminho, replace(encode(convert_to(conteudo, 'UTF8'), 'base64'), E'\n', '') from arquivos" > /tmp/arquivos.txt || return 1
	local n=0
	while IFS='|' read -r caminho b64; do
		case "$caminho" in
			contas/*.json|usuarios/*.json) ;;
			*) continue ;;
		esac
		case "$caminho" in *..*|*/*/*) continue ;; esac
		mkdir -p "$DADOS/$(dirname "$caminho")"
		printf '%s' "$b64" | base64 -d > "$DADOS/$caminho" && n=$((n + 1))
	done < /tmp/arquivos.txt
	echo "banco de dados: $n arquivo(s) restaurado(s)"
	touch /tmp/ultima_sinc
	return 0
}

sincronizar_enviar() {
	[ -z "$DB" ] && return 0
	[ -f /tmp/ultima_sinc ] || touch -d '1970-01-01' /tmp/ultima_sinc
	touch /tmp/sinc_inicio
	local lista
	lista=$(cd "$DADOS" && find contas usuarios -maxdepth 1 -type f -name '*.json' -newer /tmp/ultima_sinc 2>/dev/null)
	if [ -z "$lista" ]; then
		mv /tmp/sinc_inicio /tmp/ultima_sinc
		return 0
	fi
	echo "begin;" > /tmp/sinc.sql
	for f in $lista; do
		printf "insert into arquivos (caminho, conteudo, atualizado) values ('%s', convert_from(decode('%s', 'base64'), 'UTF8'), now()) on conflict (caminho) do update set conteudo = excluded.conteudo, atualizado = now();\n" \
			"$f" "$(base64 -w0 "$DADOS/$f")" >> /tmp/sinc.sql
	done
	echo "commit;" >> /tmp/sinc.sql
	if psql "$DB" -q -v ON_ERROR_STOP=1 -f /tmp/sinc.sql > /dev/null; then
		mv /tmp/sinc_inicio /tmp/ultima_sinc
		echo "banco de dados: $(echo "$lista" | wc -l) arquivo(s) salvo(s)"
	else
		echo "banco de dados: falha ao salvar (tenta de novo em 20 s)"
	fi
}

encerrar() {
	# o Render manda TERM quando o servidor vai dormir ou ser trocado: salva tudo antes de sair
	ENCERRANDO=1
	echo "encerrando: salvando o progresso"
	touch "$SAIR"
	for _ in $(seq 1 15); do
		[ -n "${PID:-}" ] && kill -0 "$PID" 2>/dev/null || break
		sleep 1
	done
	sincronizar_enviar
	exit 0
}
trap encerrar TERM INT

LOGIN=""
if [ -n "$DB" ]; then
	until sincronizar_baixar; do
		echo "banco de dados indisponível; tentando de novo em 10 s"
		sleep 10
	done
	LOGIN="--exigir-login"
else
	echo "AVISO: sem DATABASE_URL, o servidor roda sem login e o progresso fica com os jogadores (cópia assinada)"
fi
if [ -z "${SEGREDO_SAVES:-}" ]; then
	echo "AVISO: sem SEGREDO_SAVES"
fi
if [ "${SEM_NGINX:-0}" != "1" ]; then
	sed "s/__PORTA__/$PORTA/" "$APP/nginx.conf" > /tmp/nginx_seneca.conf
	nginx -c /tmp/nginx_seneca.conf
fi

baixar_versao() {
	curl -fsSL "$BASE/versao.json?t=$(date +%s)" -o /tmp/versao_nova.json || return 1
	local bin_novo pck_novo
	bin_novo=$(jq -r .binario /tmp/versao_nova.json)
	pck_novo=$(jq -r .pacote /tmp/versao_nova.json)
	if [ ! -f "$DIR/binario.txt" ] || [ "$(cat "$DIR/binario.txt")" != "$bin_novo" ]; then
		echo "baixando o motor do servidor ($bin_novo)"
		curl -fsSL "$BASE/seneca_servidor.x86_64.gz?v=$bin_novo" -o /tmp/srv.gz || return 1
		gunzip -c /tmp/srv.gz > "$DIR/seneca_servidor.x86_64.novo" || return 1
		chmod +x "$DIR/seneca_servidor.x86_64.novo"
		mv "$DIR/seneca_servidor.x86_64.novo" "$DIR/seneca_servidor.x86_64"
		echo "$bin_novo" > "$DIR/binario.txt"
		rm -f /tmp/srv.gz
	fi
	if [ ! -f "$DIR/pacote.txt" ] || [ "$(cat "$DIR/pacote.txt")" != "$pck_novo" ]; then
		echo "baixando o pacote do jogo ($pck_novo)"
		curl -fsSL "$BASE/seneca_servidor.pck?v=$pck_novo" -o "$DIR/seneca_servidor.pck.novo" || return 1
		mv "$DIR/seneca_servidor.pck.novo" "$DIR/seneca_servidor.pck"
		echo "$pck_novo" > "$DIR/pacote.txt"
	fi
	cp /tmp/versao_nova.json "$DIR/versao.json"
	return 0
}

versao_mudou() {
	curl -fsSL "$BASE/versao.json?t=$(date +%s)" -o /tmp/versao_check.json || return 1
	[ "$(jq -r '.binario + .pacote' /tmp/versao_check.json)" != "$(jq -r '.binario + .pacote' "$DIR/versao.json")" ]
}

jogadores() {
	jq -r '.jogadores // 0' "$STATUS" 2>/dev/null || echo 0
}

while true; do
	until baixar_versao; do
		echo "sem acesso ao GitHub; tentando de novo em 20 s"
		sleep 20
	done
	echo "iniciando o servidor, versão $(jq -r .versao "$DIR/versao.json")"
	rm -f "$SAIR"
	"$DIR/seneca_servidor.x86_64" --headless -- --servidor --ws-porta=24681 --sem-udp --endereco=127.0.0.1 $LOGIN \
		--dados="$DADOS" --status="$STATUS" --sair="$SAIR" --nome="Servidor online SENECA REBORN" &
	PID=$!
	ultimo_check=$(date +%s)
	ultima_sinc=$(date +%s)
	while kill -0 $PID 2>/dev/null; do
		sleep 10 &
		wait $!
		agora=$(date +%s)
		if [ $((agora - ultima_sinc)) -ge 20 ]; then
			ultima_sinc=$agora
			sincronizar_enviar
		fi
		if [ $((agora - ultimo_check)) -ge 120 ]; then
			ultimo_check=$agora
			if versao_mudou && [ "$(jogadores)" = "0" ]; then
				echo "versão nova publicada e ninguém jogando: atualizando o servidor"
				touch "$SAIR"
				for _ in $(seq 1 30); do kill -0 $PID 2>/dev/null || break; sleep 1; done
				kill $PID 2>/dev/null
			fi
		fi
	done
	wait $PID 2>/dev/null
	sincronizar_enviar
	[ "$ENCERRANDO" = "1" ] && exit 0
	echo '{"estado": "reiniciando"}' > "$STATUS"
	sleep 5
done
