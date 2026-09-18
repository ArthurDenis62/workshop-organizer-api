#!/usr/bin/env bash
#
# backup-volume.sh - Sauvegarde physique (à froid) du volume PostgreSQL.
# Arrête brièvement l'application et la base pour garantir la cohérence des fichiers.
#
# Usage : ./scripts/backup-volume.sh
# Variables : BACKUP_DIR (défaut ./backups), RETENTION_DAYS (défaut 28)
# Planification (cron, le dimanche à 3h) :
#   0 3 * * 0 cd /opt/workshop-organizer-api && ./scripts/backup-volume.sh >> /var/log/workshop-backup.log 2>&1
#
set -Eeuo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

BACKUP_DIR="$(mkdir -p "${BACKUP_DIR:-./backups}" && cd "${BACKUP_DIR:-./backups}" && pwd)"
RETENTION_DAYS="${RETENTION_DAYS:-28}"
PROJECT="${COMPOSE_PROJECT_NAME:-workshop-organizer}"
VOLUME="${PROJECT}_pgdata"
ARCHIVE="pgdata_$(date +%Y%m%d_%H%M%S).tar.gz"

echo "[backup-volume] $(date '+%Y-%m-%dT%H:%M:%S') arrêt des services"
docker compose stop app db

# Redémarre les services même si l'archivage échoue
trap 'docker compose up -d --wait db app' EXIT

docker run --rm -v "${VOLUME}":/data:ro -v "${BACKUP_DIR}":/backup alpine \
    tar -czf "/backup/${ARCHIVE}" -C /data .
( cd "$BACKUP_DIR" && shasum -a 256 "$ARCHIVE" > "${ARCHIVE}.sha256" )

find "$BACKUP_DIR" -type f -name 'pgdata_*' -mtime +"$RETENTION_DAYS" -print -delete

echo "[backup-volume] OK : ${BACKUP_DIR}/${ARCHIVE} ($(du -h "${BACKUP_DIR}/${ARCHIVE}" | cut -f1))"
