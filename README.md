# Workshop Organizer Web API

Welcome to the Workshop Organizer Web API! This application is designed to facilitate workshops open to the public. Whether you’re organizing coding bootcamps, art classes, or any other type of workshop, this API will help manage registrations, schedules, and resources.

## Table of Contents

1. Context
2. Technical Overview
3. Building and Running
4. Testing
5. Packaging
6. Publishing to GitLab Registry

## Context

Workshops play a crucial role in fostering learning and collaboration. Our application aims to streamline the workshop organization process, making it easier for organizers to manage participants, sessions, and materials. Whether you're a seasoned workshop host or just starting out, this API has got you covered!

## Technical Overview

- **Java Development Kit (JDK):** We use **JDK 21**, tested with **Adoptium**, to power our application.
- **Database:** Our backend relies on a **PostgreSQL 13** database for data storage.
- **Build Tool:** We leverage **Gradle 8.7** for managing dependencies and building the project.
- **Spring Boot:** Our application is based on **Spring Boot 3.2.4**, which provides a robust framework for creating RESTful APIs.
- **Application Server:** Our application can run on Tomcat server that require version 10.1.24.

## Building and Running

To compile and run the application locally, follow these steps:

1. Ensure you have JDK 21 installed.
2. Clone this repository.
3. Navigate to the project root directory.
4. Execute the following command to compile the Java code :
   ```bash
   ./gradlew clean compileJava
   ```
5. To run the application locally, either:
   Execute the main method in the Application class from your IDE.
   Use the Spring Boot Gradle Plugin :
   ```bash
   ./gradlew bootRun
   ```
   For production, package the application as WAR and use a tomcat server

To run correctly the application with docker after you building it with tag workshop-organizer, run the following

```bash
docker compose up -d
```

## Configuration

You can configure the application with these environment variables

- SPRING_DATASOURCE_URL: JDBC URI for DB access (ex. jdbc:postgresql://db:5432/mydatabase)
- SPRING_DATASOURCE_USERNAME: Database user name used by the application
- SPRING_DATASOURCE_PASSWORD: Database user password used by the application

## Testing

We take testing seriously! To verify the correctness of our application, run the following command:

```bash
./gradlew clean test
```

During execution junit reports are generated in the `build/test-results/test` folder.

## Packaging

When you’re ready to package the application for deployment, create a deployable WAR file:

```bash
./gradlew bootWar
```

The generated war file can be used with many application servers such as Tomcat, Wildfly...

## Publishing to GitLab Registry

To publish your application to a GitLab registry, follow these steps:

1. Set up your GitLab project.
2. Ensure you have the following environment variables configured:

   - GITLAB_PROJECT_ID: The ID of your GitLab project.
   - GITLAB_TOKEN_NAME: The name of the GitLab access token.
   - GITLAB_TOKEN: Your GitLab access token.

3. Execute the following command to publish your application:
   ```bash
   ./gradlew publish
   ```
   Remember to replace placeholders with actual values specific to your project.

Feel free to enhance this README with additional details, such as API endpoints, security considerations, and deployment instructions. Happy organizing! 🚀

---

## Industrialisation : Docker & CI/CD

### Lancer l'application avec Docker

Prérequis : Docker 24+ et Docker Compose v2.

```bash
cp .env.example .env   # puis adapter les identifiants (facultatif en local)
docker compose up -d --build
```

- API : http://localhost:8080/api/workshops, http://localhost:8080/api/notions
- Documentation OpenAPI (Swagger UI) : http://localhost:8080/
- Santé : http://localhost:8080/actuator/health, métriques : `/actuator/metrics`, `/actuator/prometheus`

| Fichier | Rôle |
|---|---|
| `Dockerfile` | Build multi-stage : `eclipse-temurin:21-jdk` compile avec Gradle (`bootJar`), `eclipse-temurin:21-jre-alpine` exécute le JAR (utilisateur non-root) |
| `.dockerignore` | Exclut `build/`, `.gradle/`, sources générées, fichiers Git/IDE du contexte de build |
| `docker-compose.yml` | Services `db` (PostgreSQL 13, volume `pgdata`, healthcheck `pg_isready`) et `app` (démarre quand la base est *healthy*) |
| `db/docker-init/01-init-db.sh` | Rejoue `db/00001_0.0.0_init_create.sql` au premier démarrage de PostgreSQL (volume vide) |
| `.env.example` | Variables de configuration (base, port, image) |

Variables d'environnement de l'application : `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`,
`SPRING_DATASOURCE_PASSWORD` (renseignées par `docker-compose.yml` à partir de `.env`).

### Exécuter les tests

```bash
./run-tests.sh
```

Le script détecte le type de projet, vérifie les prérequis (JDK 21+), exécute `./gradlew cleanTest test` et place les
rapports JUnit XML dans `test-results/` (couverture JaCoCo dans `test-results/coverage/`).
Codes de sortie : `0` succès, `1` tests en échec, `2` environnement invalide, `3` aucun rapport produit.

### Pipeline CI/CD (GitHub Actions)

Le workflow `.github/workflows/ci.yml` est générique (même fichier pour le front-end Angular) :

1. **detect** : type de projet via `./run-tests.sh --detect`
2. **test** : `./run-tests.sh`, rapport JUnit publié dans l'onglet *Checks*, résultats archivés en artefact
3. **build** : image Docker construite, validée par un smoke test `docker compose up --wait` (API + PostgreSQL),
   puis poussée sur `ghcr.io/<owner>/<repo>` avec les tags `<branche>`, `<branche>-<sha>`, `sha-<sha>` (+ `latest` sur `main`)
4. **release** (branche `main`) : [semantic-release](https://semantic-release.gitbook.io/) calcule la version à partir
   des commits conventionnels, crée le tag Git et la GitHub Release, puis ajoute les tags `X.Y.Z` et `X.Y` à l'image.

### Sauvegarde et restauration de la base

```bash
./scripts/backup-db.sh                                   # dump pg_dump + empreinte SHA-256 + archive de config dans backups/
./scripts/backup-volume.sh                               # copie physique du volume, à froid (hebdomadaire)
./scripts/restore-db.sh backups/workshopsdb_<date>.dump  # restauration (application arrêtée pendant l'opération)
```

Rétention par défaut : 7 jours (`RETENTION_DAYS`). Voir le dossier d'exploitation pour la stratégie complète.
