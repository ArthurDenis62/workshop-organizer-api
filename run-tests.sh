#!/usr/bin/env bash
#
# run-tests.sh - Script unifié d'exécution des tests unitaires.
#
# Détecte automatiquement le type de projet (Angular ou Spring Boot/Gradle),
# vérifie les prérequis, exécute les tests et regroupe les rapports JUnit XML
# (et de couverture) dans le répertoire test-results/.
#
# Usage : ./run-tests.sh [répertoire_du_projet]            exécute les tests
#         ./run-tests.sh --detect [répertoire_du_projet]   affiche le type détecté
#         (répertoire par défaut : dossier du script)
#
# Variables optionnelles :
#   PROJECT_TYPE   force le type de projet (angular | gradle | maven)
#   CHROME_BIN     navigateur utilisé par Karma (détecté automatiquement sinon)
#
# Codes de sortie :
#   0  tous les tests sont passés
#   1  au moins un test en échec
#   2  environnement invalide (type de projet inconnu, outil manquant...)
#   3  aucun rapport JUnit n'a été produit
#
set -Eeuo pipefail

readonly EXIT_OK=0
readonly EXIT_TEST_FAILURE=1
readonly EXIT_ENV_ERROR=2
readonly EXIT_NO_REPORT=3

DETECT_ONLY=false
if [[ "${1:-}" == "--detect" ]]; then
    DETECT_ONLY=true
    shift
fi

PROJECT_DIR="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}" && pwd)"
RESULTS_DIR="${PROJECT_DIR}/test-results"

log()  { printf '\033[1;34m[run-tests]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[run-tests] ERREUR:\033[0m %s\n' "$1" >&2; exit "${2:-$EXIT_ENV_ERROR}"; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "commande '$1' introuvable. $2"
}

# Vérifie qu'une version majeure est >= au minimum attendu
require_min_major() {
    local name="$1" current="$2" minimum="$3"
    [[ "$current" =~ ^[0-9]+$ ]] || fail "impossible de déterminer la version de ${name}."
    (( current >= minimum )) || fail "${name} ${minimum}+ requis (version détectée : ${current})."
}

detect_project_type() {
    if [[ -n "${PROJECT_TYPE:-}" ]]; then
        echo "$PROJECT_TYPE"
    elif [[ -f "${PROJECT_DIR}/angular.json" && -f "${PROJECT_DIR}/package.json" ]]; then
        echo "angular"
    elif [[ -f "${PROJECT_DIR}/gradlew" || -f "${PROJECT_DIR}/build.gradle" || -f "${PROJECT_DIR}/build.gradle.kts" ]]; then
        echo "gradle"
    elif [[ -f "${PROJECT_DIR}/pom.xml" ]]; then
        echo "maven"
    else
        echo "unknown"
    fi
}

# Nettoie les résultats d'une exécution précédente pour ne jamais publier
# de rapports obsolètes
clean_previous_results() {
    log "Nettoyage des artefacts de tests précédents"
    rm -rf "${RESULTS_DIR}" "$@"
    mkdir -p "${RESULTS_DIR}"
}

# Copie les rapports JUnit trouvés dans $1 vers test-results/
collect_junit_reports() {
    local source_dir="$1" count=0
    if [[ -d "$source_dir" ]]; then
        while IFS= read -r -d '' report; do
            cp "$report" "${RESULTS_DIR}/"
            count=$((count + 1))
        done < <(find "$source_dir" -name '*.xml' -type f -print0)
    fi
    echo "$count"
}

find_chrome() {
    if [[ -n "${CHROME_BIN:-}" && -x "${CHROME_BIN}" ]]; then
        echo "$CHROME_BIN"; return
    fi
    local candidate
    for candidate in google-chrome google-chrome-stable chromium chromium-browser \
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
        "/Applications/Chromium.app/Contents/MacOS/Chromium"; do
        if command -v "$candidate" >/dev/null 2>&1; then
            command -v "$candidate"; return
        elif [[ -x "$candidate" ]]; then
            echo "$candidate"; return
        fi
    done
}

run_angular_tests() {
    require_cmd node "Installez Node.js 20+ (https://nodejs.org)."
    require_cmd npm  "Installez npm (fourni avec Node.js)."
    require_min_major "Node.js" "$(node -p 'process.versions.node.split(".")[0]')" 20

    local chrome
    chrome="$(find_chrome)"
    [[ -n "$chrome" ]] || fail "aucun navigateur Chrome/Chromium trouvé pour Karma (définissez CHROME_BIN)."
    export CHROME_BIN="$chrome"

    clean_previous_results "${PROJECT_DIR}/reports" "${PROJECT_DIR}/coverage"

    if [[ ! -d "${PROJECT_DIR}/node_modules" ]]; then
        log "node_modules absent : installation des dépendances (npm ci)"
        npm ci --no-audit --no-fund --prefix "${PROJECT_DIR}"
    fi

    log "Exécution des tests Angular (Karma + Jasmine, Chrome headless)"
    local rc=0
    (cd "${PROJECT_DIR}" && npx ng test --watch=false --code-coverage --browsers=ChromeHeadless) || rc=$?

    REPORT_COUNT="$(collect_junit_reports "${PROJECT_DIR}/reports")"
    if [[ -d "${PROJECT_DIR}/coverage" ]]; then
        cp -R "${PROJECT_DIR}/coverage" "${RESULTS_DIR}/coverage"
    fi
    return "$rc"
}

run_gradle_tests() {
    require_cmd java "Installez un JDK 21 (ex. Eclipse Temurin)."
    local java_major
    java_major="$(java -version 2>&1 | awk -F'"' '/version/ {split($2, v, "."); print (v[1] == "1" ? v[2] : v[1]); exit}')"
    require_min_major "Java" "$java_major" 21

    local gradle_cmd="gradle"
    if [[ -f "${PROJECT_DIR}/gradlew" ]]; then
        chmod +x "${PROJECT_DIR}/gradlew"
        gradle_cmd="./gradlew"
    else
        require_cmd gradle "Ajoutez le wrapper Gradle ou installez Gradle."
    fi

    clean_previous_results "${PROJECT_DIR}/build/test-results" "${PROJECT_DIR}/build/reports/jacoco"

    log "Exécution des tests Spring Boot (JUnit 5 via Gradle)"
    local rc=0
    (cd "${PROJECT_DIR}" && "$gradle_cmd" cleanTest test --no-daemon --console=plain) || rc=$?

    REPORT_COUNT="$(collect_junit_reports "${PROJECT_DIR}/build/test-results/test")"
    if [[ -d "${PROJECT_DIR}/build/reports/jacoco/test" ]]; then
        cp -R "${PROJECT_DIR}/build/reports/jacoco/test" "${RESULTS_DIR}/coverage"
    fi
    return "$rc"
}

run_maven_tests() {
    local mvn_cmd="mvn"
    if [[ -f "${PROJECT_DIR}/mvnw" ]]; then
        mvn_cmd="./mvnw"
    else
        require_cmd mvn "Installez Maven."
    fi
    clean_previous_results "${PROJECT_DIR}/target/surefire-reports"

    log "Exécution des tests Maven (Surefire)"
    local rc=0
    (cd "${PROJECT_DIR}" && "$mvn_cmd" -B test) || rc=$?

    REPORT_COUNT="$(collect_junit_reports "${PROJECT_DIR}/target/surefire-reports")"
    return "$rc"
}

# Affiche un résumé à partir des rapports JUnit collectés
print_summary() {
    local tests=0 failures=0 errors=0 skipped=0 file attr value
    for file in "${RESULTS_DIR}"/*.xml; do
        [[ -f "$file" ]] || continue
        for attr in tests failures errors skipped; do
            # Premier <testsuite> de chaque fichier (un fichier = une suite)
            value="$(grep -o "<testsuite [^>]*" "$file" | head -1 | grep -o " ${attr}=\"[0-9]*\"" | grep -o '[0-9]*' || true)"
            value="${value:-0}"
            case "$attr" in
                tests)    tests=$((tests + value)) ;;
                failures) failures=$((failures + value)) ;;
                errors)   errors=$((errors + value)) ;;
                skipped)  skipped=$((skipped + value)) ;;
            esac
        done
    done
    log "Résumé : ${tests} test(s), ${failures} échec(s), ${errors} erreur(s), ${skipped} ignoré(s)"
    log "Rapports JUnit : ${RESULTS_DIR}"
}

main() {
    local type
    type="$(detect_project_type)"

    # Mode utilisé par le pipeline CI pour choisir les outils à installer
    if [[ "$DETECT_ONLY" == true ]]; then
        echo "$type"
        [[ "$type" != "unknown" ]]
        return
    fi

    log "Projet : ${PROJECT_DIR}"
    log "Type de projet détecté : ${type}"

    REPORT_COUNT=0
    local rc=0
    case "$type" in
        angular) run_angular_tests || rc=$? ;;
        gradle)  run_gradle_tests  || rc=$? ;;
        maven)   run_maven_tests   || rc=$? ;;
        *) fail "type de projet non reconnu (angular.json, build.gradle ou pom.xml attendu)." ;;
    esac

    if (( REPORT_COUNT == 0 )); then
        fail "aucun rapport JUnit XML généré (code de sortie des tests : ${rc})." "$EXIT_NO_REPORT"
    fi

    print_summary

    if (( rc != 0 )); then
        fail "des tests sont en échec (code ${rc})." "$EXIT_TEST_FAILURE"
    fi
    log "Tous les tests sont passés"
    exit "$EXIT_OK"
}

main "$@"
