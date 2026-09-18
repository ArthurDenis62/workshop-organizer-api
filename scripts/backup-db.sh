#!/usr/bin/env bash
#
# backup-db.sh - Sauvegarde logique de la base PostgreSQL (pg_dump, format custom)
# et archive des fichiers de configuration.
#
# Usage : ./scripts/backup-db.sh
# Variables : BACKUP_DIR (défaut ./backups), RETENTION_DAYS (défaut 7)
# Planification (cron, tous les jours à 2h) :
#   0 2 * * * cd /opt/workshop-organizer-api && ./scripts/backup-db.sh >> /var/log/workshop-backup.log 2>&1
#
set -Eeuo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Charge .env s'il existe (mêmes valeurs que docker-compose.yml)
if [[ -f .env ]]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
fi
DB_NAME="${POSTGRES_DB:-workshopsdb}"
DB_USER="${POSTGRES_USER:-workshops_user}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
STAMP="$(date +%Y%m%d_%H%M%S)"

mkdir -p "$BACKUP_DIR"
DUMP_FILE="${BACKUP_DIR}/${DB_NAME}_${STAMP}.dump"
CONFIG_FILE="${BACKUP_DIR}/config_${STAMP}.tar.gz"

echo "[backup] $(date '+%Y-%m-%dT%H:%M:%S') début de la sauvegarde de '${DB_NAME}'"

# 1. Dump de la base (à chaud, cohérent grâce à la transaction de pg_dump)
docker compose exec -T db pg_dump -U "$DB_USER" -d "$DB_NAME" --format=custom > "$DUMP_FILE"

# 2. Contrôle d'intégrité : le dump doit être lisible par pg_restore et non vide
docker compose exec -T db pg_restore --list < "$DUMP_FILE" > /dev/null
[[ -s "$DUMP_FILE" ]] || { echo "[backup] ERREUR : dump vide" >&2; exit 1; }
( cd "$BACKUP_DIR" && shasum -a 256 "$(basename "$DUMP_FILE")" > "$(basename "$DUMP_FILE").sha256" )

# 3. Archive de la configuration (compose, variables, scripts d'init)
CONFIG_ITEMS=(docker-compose.yml db/)
[[ -f .env ]] && CONFIG_ITEMS+=(.env)
tar -czf "$CONFIG_FILE" "${CONFIG_ITEMS[@]}"

# 4. Rétention : suppression des sauvegardes plus anciennes que RETENTION_DAYS
find "$BACKUP_DIR" -type f \( -name '*.dump' -o -name '*.sha256' -o -name 'config_*.tar.gz' \) \
    -mtime +"$RETENTION_DAYS" -print -delete

echo "[backup] OK : ${DUMP_FILE} ($(du -h "$DUMP_FILE" | cut -f1)), ${CONFIG_FILE}"
