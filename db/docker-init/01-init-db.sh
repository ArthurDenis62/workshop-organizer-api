#!/bin/bash
# Exécuté par l'image postgres uniquement au premier démarrage (volume vide).
# Rejoue le script d'initialisation fourni (db/00001_0.0.0_init_create.sql) en
# retirant les "OWNER TO postgres" : le rôle propriétaire est POSTGRES_USER.
set -euo pipefail

for file in /sql/*.sql; do
    echo "Initialisation de la base ${POSTGRES_DB} avec ${file}"
    sed -E '/OWNER TO postgres;/d' "$file" \
        | psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB"
done
