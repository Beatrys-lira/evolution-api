#!/bin/bash
# ============================================================
# deploy_database.sh — VERSÃO CORRIGIDA PARA RAILWAY
#
# Este script roda em RUNTIME (ao iniciar o container).
# Neste momento, as env vars do Railway JÁ estão disponíveis.
#
# Responsabilidade:
#   1. Determinar DATABASE_PROVIDER
#   2. Atualizar o .env interno com as env vars do Railway
#   3. Executar as migrations Prisma (migrate deploy)
# ============================================================

set -e

echo "==> [deploy_database.sh] Iniciando deploy do banco de dados..."
echo "==> Ambiente: $(date)"

# -----------------------------------------------------------
# PASSO 1: Determinar DATABASE_PROVIDER
# No Railway, a var já está no ambiente; se não, lê do .env
# -----------------------------------------------------------

if [ -n "$DATABASE_PROVIDER" ]; then
    PROVIDER="$DATABASE_PROVIDER"
    echo "==> DATABASE_PROVIDER (env): $PROVIDER"
elif [ -f ".env" ]; then
    PROVIDER=$(grep -E '^DATABASE_PROVIDER=' .env | head -1 | cut -d'=' -f2 | tr -d '"' | tr -d "'" | tr -d ' ')
    echo "==> DATABASE_PROVIDER (.env): $PROVIDER"
fi

PROVIDER=$(echo "${PROVIDER:-postgresql}" | tr '[:upper:]' '[:lower:]')

PRISMA_PROVIDER="$PROVIDER"
if [ "$PROVIDER" = "psql_bouncer" ]; then
    PRISMA_PROVIDER="postgresql"
fi

echo "==> Usando provider: $PROVIDER (schema: $PRISMA_PROVIDER)"

# -----------------------------------------------------------
# PASSO 2: Sincronizar env vars do Railway → .env
# (O Prisma e a aplicação lêem do .env em alguns caminhos)
# -----------------------------------------------------------

echo "==> Sincronizando variáveis de ambiente para .env..."

# Função auxiliar para atualizar ou adicionar variável no .env
update_env() {
    local key="$1"
    local value="$2"
    if [ -z "$value" ]; then
        return
    fi
    if grep -qE "^${key}=" .env 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        echo "${key}=${value}" >> .env
    fi
}

# Sincroniza as variáveis críticas
update_env "DATABASE_PROVIDER" "${DATABASE_PROVIDER}"
update_env "DATABASE_ENABLED" "${DATABASE_ENABLED}"
update_env "SERVER_PORT" "${SERVER_PORT}"
update_env "AUTHENTICATION_API_KEY" "${AUTHENTICATION_API_KEY}"
update_env "CACHE_REDIS_ENABLED" "${CACHE_REDIS_ENABLED}"

# Variável de connection: suporta tanto _URI quanto _URL
# A Evolution API usa DATABASE_CONNECTION_URI internamente
if [ -n "$DATABASE_CONNECTION_URI" ]; then
    update_env "DATABASE_CONNECTION_URI" "${DATABASE_CONNECTION_URI}"
elif [ -n "$DATABASE_CONNECTION_URL" ]; then
    # Railway frequentemente usa DATABASE_URL ou DATABASE_CONNECTION_URL
    # Mapear para o nome que a Evolution API espera
    update_env "DATABASE_CONNECTION_URI" "${DATABASE_CONNECTION_URL}"
    echo "==> AVISO: Mapeado DATABASE_CONNECTION_URL → DATABASE_CONNECTION_URI"
elif [ -n "$DATABASE_URL" ]; then
    update_env "DATABASE_CONNECTION_URI" "${DATABASE_URL}"
    echo "==> AVISO: Mapeado DATABASE_URL → DATABASE_CONNECTION_URI"
fi

# Redis (opcional)
[ -n "$CACHE_REDIS_URI" ] && update_env "CACHE_REDIS_URI" "${CACHE_REDIS_URI}"
[ -n "$CACHE_REDIS_ENABLED" ] && update_env "CACHE_REDIS_ENABLED" "${CACHE_REDIS_ENABLED}"

# -----------------------------------------------------------
# PASSO 3: Verificar connection string
# -----------------------------------------------------------
DB_URI=$(grep -E '^DATABASE_CONNECTION_URI=' .env | head -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'")

if [ -z "$DB_URI" ]; then
    echo "ERRO CRÍTICO: DATABASE_CONNECTION_URI não definido!"
    echo "Configure esta variável no Railway com a URL de conexão do PostgreSQL."
    echo "Formato: postgresql://user:password@host:5432/database?schema=public"
    exit 1
fi

echo "==> Connection string: ${DB_URI:0:40}... (truncada)"

# -----------------------------------------------------------
# PASSO 4: Executar migrations Prisma
# -----------------------------------------------------------
SCHEMA_FILE="./prisma/${PRISMA_PROVIDER}-schema.prisma"
MIGRATIONS_SRC="./prisma/${PRISMA_PROVIDER}-migrations"
MIGRATIONS_DST="./prisma/migrations"

if [ ! -f "$SCHEMA_FILE" ]; then
    echo "ERRO: Schema não encontrado: $SCHEMA_FILE"
    exit 1
fi

echo "==> Preparando migrations de: $MIGRATIONS_SRC"
rm -rf "$MIGRATIONS_DST"
cp -r "$MIGRATIONS_SRC" "$MIGRATIONS_DST"

echo "==> Executando: npx prisma migrate deploy --schema $SCHEMA_FILE"
npx prisma migrate deploy --schema "$SCHEMA_FILE"

echo "==> [deploy_database.sh] Migrations aplicadas com sucesso!"
echo "==> Iniciando aplicação..."
