#!/bin/bash

source ./Docker/scripts/env_functions.sh

if [ "$DOCKER_ENV" != "true" ]; then
    export_env_vars
fi

# Resolve DATABASE_CONNECTION_URI from Railway's environment variables.
# Railway sets DATABASE_URL directly; fall back to constructing it from
# individual PG* variables if DATABASE_CONNECTION_URI is not already set.
if [ -z "$DATABASE_CONNECTION_URI" ]; then
    if [ -n "$DATABASE_URL" ]; then
        export DATABASE_CONNECTION_URI="$DATABASE_URL"
    elif [ -n "$PGHOST" ] && [ -n "$PGPORT" ] && [ -n "$PGUSER" ] && [ -n "$PGPASSWORD" ] && [ -n "$PGDATABASE" ]; then
        export DATABASE_CONNECTION_URI="postgresql://${PGUSER}:${PGPASSWORD}@${PGHOST}:${PGPORT}/${PGDATABASE}?schema=evolution_api"
    fi
fi

if [[ "$DATABASE_PROVIDER" == "postgresql" || "$DATABASE_PROVIDER" == "mysql" || "$DATABASE_PROVIDER" == "psql_bouncer" ]]; then
    export DATABASE_CONNECTION_URI
    echo "Deploying migrations for $DATABASE_PROVIDER"
    echo "Database URL: $DATABASE_CONNECTION_URI"
    # rm -rf ./prisma/migrations
    # cp -r ./prisma/$DATABASE_PROVIDER-migrations ./prisma/migrations
    npm run db:deploy
    if [ $? -ne 0 ]; then
        echo "Migration failed"
        exit 1
    else
        echo "Migration succeeded"
    fi
    npm run db:generate
    if [ $? -ne 0 ]; then
        echo "Prisma generate failed"
        exit 1
    else
        echo "Prisma generate succeeded"
    fi
else
    echo "Error: Database provider $DATABASE_PROVIDER invalid."
    exit 1
fi
