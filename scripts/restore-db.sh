#!/usr/bin/env bash
#
# restore-db.sh - Restaure la base PostgreSQL depuis un dump produit par backup-db.sh
#
# Usage : ./scripts/restore-db.sh backups/workshopsdb_AAAAMMJJ_HHMMSS.dump
#
set -Eeuo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

DUMP_FILE="${1:?Usage : $0 <fichier.dump>}"
[[ -f "$DUMP_FILE" ]] || { echo "[restore] ERREUR : fichier introuvable : $DUMP_FILE" >&2; exit 1; }

if [[ -f .env ]]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
fi
DB_NAME="${POSTGRES_DB:-workshopsdb}"
DB_USER="${POSTGRES_USER:-workshops_user}"

# 1. Vérification de l'empreinte si elle existe
if [[ -f "${DUMP_FILE}.sha256" ]]; then
    ( cd "$(dirname "$DUMP_FILE")" && shasum -a 256 -c "$(basename "$DUMP_FILE").sha256" )
fi

echo "[restore] $(date '+%Y-%m-%dT%H:%M:%S') restauration de '${DB_NAME}' depuis ${DUMP_FILE}"

# 2. Base démarrée, application arrêtée (aucune écriture pendant la restauration)
docker compose up -d --wait db
docker compose stop app

# 3. Restauration : suppression puis recréation des objets du dump, en une transaction
docker compose exec -T db pg_restore -U "$DB_USER" -d "$DB_NAME" \
    --clean --if-exists --no-owner --single-transaction < "$DUMP_FILE"

# 4. Redémarrage de l'application et attente du healthcheck
docker compose up -d --wait app

# 5. Vérification du contenu restauré
docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -c \
    "SELECT (SELECT count(*) FROM workshop_model) AS workshops, (SELECT count(*) FROM notion_model) AS notions;"
echo "[restore] OK"
