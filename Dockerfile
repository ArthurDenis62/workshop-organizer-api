# syntax=docker/dockerfile:1

# =========================================================
# Stage 1 - Build : compile l'application avec Gradle (JDK)
# =========================================================
FROM eclipse-temurin:21-jdk AS builder

WORKDIR /workspace

# Wrapper + scripts Gradle en premier : cette couche (et le téléchargement
# des dépendances) reste en cache tant que la configuration ne change pas.
COPY gradlew settings.gradle build.gradle ./
COPY gradle ./gradle
RUN chmod +x gradlew \
    && ./gradlew dependencies --no-daemon -q > /dev/null

# Sources (dont la spec OpenAPI utilisée pour générer les interfaces)
COPY src ./src

# Les tests sont exécutés par le pipeline CI (run-tests.sh), pas au build de l'image
RUN ./gradlew bootJar -x test --no-daemon \
    && cp build/libs/*.jar /workspace/app.jar

# =========================================================
# Stage 2 - Runtime : JRE seule, utilisateur non-root
# =========================================================
FROM eclipse-temurin:21-jre-alpine

LABEL org.opencontainers.image.title="workshop-organizer-api" \
      org.opencontainers.image.description="Workshop Organizer Web API (Spring Boot)"

RUN addgroup -S spring && adduser -S -G spring -H spring

WORKDIR /app
COPY --from=builder --chown=spring:spring /workspace/app.jar app.jar

USER spring

EXPOSE 8080

# Options JVM ajustables sans reconstruire l'image
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75.0"

HEALTHCHECK --interval=15s --timeout=5s --start-period=60s --retries=5 \
    CMD ["wget", "-qO-", "http://localhost:8080/actuator/health"]

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
