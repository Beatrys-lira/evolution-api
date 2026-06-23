#!/bin/bash
# ============================================================
# generate_database.sh — VERSÃO CORRIGIDA PARA RAILWAY
#
# PROBLEMA ORIGINAL:
#   O script original faz: [ ! -f .env ] && echo ".env file not found" && exit 1
#   No Railway, o build Docker NÃO tem acesso às env vars do projeto.
#   O .env.example é copiado como .env, mas DATABASE_PROVIDER pode
#   estar com valor padrão ou ausente dependendo da versão.
#
# SOLUÇÃO:
#   1. Aceitar DATABASE_PROVIDER tanto do .env quanto da variável de ambiente
#   2. Se .env não existir, criar um mínimo funcional
#   3. Não falhar se o .env tiver valores placeholder
# ============================================================

set -e

# Diretório de trabalho
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

cd "$ROOT_DIR"

echo "==> [generate_database.sh] Iniciando geração do cliente Prisma..."

# -----------------------------------------------------------
# PASSO 1: Determinar DATABASE_PROVIDER
# Prioridade: variável de ambiente > .env > padrão postgresql
# -----------------------------------------------------------

# Tenta ler do .env se existir
if [ -f ".env" ]; then
    echo "==> Arquivo .env encontrado, lendo configurações..."
    # Extrai DATABASE_PROVIDER do .env (ignora comentários e linhas em branco)
    ENV_PROVIDER=$(grep -E '^DATABASE_PROVIDER=' .env | head -1 | cut -d'=' -f2 | tr -d '"' | tr -d "'" | tr -d ' ')
else
    echo "==> Arquivo .env não encontrado, criando .env mínimo a partir do .env.example..."
    if [ -f ".env.example" ]; then
        cp .env.example .env
        ENV_PROVIDER=$(grep -E '^DATABASE_PROVIDER=' .env | head -1 | cut -d'=' -f2 | tr -d '"' | tr -d "'" | tr -d ' ')
    else
        echo "==> AVISO: .env.example também não encontrado. Usando padrão postgresql."
        ENV_PROVIDER=""
    fi
fi

# Variável de ambiente tem prioridade máxima
if [ -n "$DATABASE_PROVIDER" ]; then
    echo "==> DATABASE_PROVIDER definido via variável de ambiente: $DATABASE_PROVIDER"
    PROVIDER="$DATABASE_PROVIDER"
elif [ -n "$ENV_PROVIDER" ]; then
    echo "==> DATABASE_PROVIDER lido do .env: $ENV_PROVIDER"
    PROVIDER="$ENV_PROVIDER"
else
    echo "==> DATABASE_PROVIDER não definido. Usando padrão: postgresql"
    PROVIDER="postgresql"
fi

# Normaliza para minúsculo
PROVIDER=$(echo "$PROVIDER" | tr '[:upper:]' '[:lower:]')

# -----------------------------------------------------------
# PASSO 2: Validar o provider
# -----------------------------------------------------------
case "$PROVIDER" in
    postgresql|mysql|psql_bouncer)
        echo "==> Provider válido: $PROVIDER"
        ;;
    *)
        echo "==> AVISO: Provider '$PROVIDER' inválido ou não reconhecido. Usando postgresql como fallback."
        PROVIDER="postgresql"
        ;;
esac

# Para psql_bouncer, o schema Prisma a usar é o postgresql
PRISMA_PROVIDER="$PROVIDER"
if [ "$PROVIDER" = "psql_bouncer" ]; then
    PRISMA_PROVIDER="postgresql"
fi

# -----------------------------------------------------------
# PASSO 3: Verificar se o schema Prisma existe
# -----------------------------------------------------------
SCHEMA_FILE="./prisma/${PRISMA_PROVIDER}-schema.prisma"

if [ ! -f "$SCHEMA_FILE" ]; then
    echo "ERRO: Schema Prisma não encontrado: $SCHEMA_FILE"
    echo "Schemas disponíveis em ./prisma/:"
    ls ./prisma/*.prisma 2>/dev/null || echo "(nenhum schema encontrado)"
    exit 1
fi

echo "==> Usando schema: $SCHEMA_FILE"

# -----------------------------------------------------------
# PASSO 4: Atualizar o .env com o provider correto
# (para que o runWithProvider.js leia corretamente em runtime)
# -----------------------------------------------------------
if grep -qE '^DATABASE_PROVIDER=' .env 2>/dev/null; then
    sed -i "s|^DATABASE_PROVIDER=.*|DATABASE_PROVIDER=${PROVIDER}|" .env
else
    echo "DATABASE_PROVIDER=${PROVIDER}" >> .env
fi

# -----------------------------------------------------------
# PASSO 5: Gerar o cliente Prisma
# -----------------------------------------------------------
echo "==> Gerando cliente Prisma para provider: $PROVIDER..."
npx prisma generate --schema "$SCHEMA_FILE"

echo "==> [generate_database.sh] Cliente Prisma gerado com sucesso!"
