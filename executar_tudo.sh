#!/usr/bin/env bash
# Recria o banco do zero e executa todos os scripts em ordem, salvando a
# saída de cada etapa em docs/saidas/.
#
# Uso:   ./executar_tudo.sh
# Config (variáveis de ambiente do psql): PGHOST, PGPORT, PGUSER, PGPASSWORD
#   DB=nome_do_banco  (padrão: sistema_express)
#
# O usuário precisa poder criar banco e roles (ex.: postgres).
set -euo pipefail
cd "$(dirname "$0")"

DB="${DB:-sistema_express}"
mkdir -p docs/saidas

echo ">> Recriando o banco $DB"
psql -q -d postgres -v ON_ERROR_STOP=1 \
     -c "DROP DATABASE IF EXISTS \"$DB\" WITH (FORCE)" \
     -c "CREATE DATABASE \"$DB\""

# arquivo : opções extras do psql
# 04 e 07 contêm erros PROPOSITAIS (demonstram SAVEPOINT e permissão negada),
# por isso rodam sem ON_ERROR_STOP.
run() {
    local arq="$1"; shift
    echo ">> $arq"
    psql -d "$DB" -a "$@" -f "sql/$arq.sql" > "docs/saidas/$arq.txt" 2>&1
}

run 01_ddl              -v ON_ERROR_STOP=1
run 02_indices          -v ON_ERROR_STOP=1
run 03_carga_dados      -v ON_ERROR_STOP=1
run 04_transacoes
run 05_explain_analyze  -v ON_ERROR_STOP=1
run 06_controle_acesso  -v ON_ERROR_STOP=1
run 07_testes_acesso

echo ">> Concluído. Saídas em docs/saidas/"
