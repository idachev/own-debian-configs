#!/bin/bash

# Postgres Schema Structure Download Script

# Check required environment variables
if [ -z "$JDBC_URL" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ] || [ -z "$SCHEMA_NAME" ]; then
    echo "Error: Missing required environment variables"
    echo "Required: JDBC_URL, DB_USER, DB_PASSWORD, SCHEMA_NAME"
    echo "Optional: PG_VERSION"
    echo "Usage: JDBC_URL=\"jdbc:postgresql://host:port/database\" DB_USER=<user> DB_PASSWORD=<password> SCHEMA_NAME=<schema> $0"
    exit 1
fi

if [ -z "PG_VERSION" ]; then
    PG_VERSION="17"
fi

# Parse JDBC URL: jdbc:postgresql://host:port/database
# Remove jdbc:postgresql:// prefix
URL_WITHOUT_PREFIX="${JDBC_URL#jdbc:postgresql://}"

# Extract host:port and database
HOST_PORT="${URL_WITHOUT_PREFIX%/*}"
DB_NAME="${URL_WITHOUT_PREFIX#*/}"

# Extract host and port
DB_HOST="${HOST_PORT%:*}"
DB_PORT="${HOST_PORT#*:}"

# Check if host is localhost/127.0.0.1 and replace with host.docker.internal for Docker
DOCKER_HOST="$DB_HOST"
if [ "$DB_HOST" = "localhost" ] || [ "$DB_HOST" = "127.0.0.1" ]; then
    DOCKER_HOST="host.docker.internal"
    DOCKER_EXTRA_ARGS="--add-host=host.docker.internal:host-gateway"
    echo "Detected localhost connection, using host.docker.internal for Docker"
else
    DOCKER_EXTRA_ARGS=""
fi

# Optional output file (defaults to schema_name_structure_timestamp.sql)
OUTPUT_FILE="${OUTPUT_FILE:-${SCHEMA_NAME}_structure_$(date +%Y%m%d_%H%M%S).sql}"

echo "Downloading schema structure for '$SCHEMA_NAME' from database '$DB_NAME' at $DB_HOST:$DB_PORT..."
echo "Using Postgres ${PG_VERSION} Docker image..."

# Use Docker with Postgres image for pg_dump with schema-only
docker run --rm \
    $DOCKER_EXTRA_ARGS \
    -e PGPASSWORD="$DB_PASSWORD" \
    -v "$(pwd):/output" \
    "postgres:${PG_VERSION}" \
    pg_dump \
    -h "$DOCKER_HOST" \
    -p "$DB_PORT" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -n "$SCHEMA_NAME" \
    -v \
    --schema-only \
    --no-owner \
    --no-privileges \
    -f "/output/$OUTPUT_FILE"

# Check if pg_dump was successful
if [ $? -eq 0 ]; then
    echo "Schema structure successfully downloaded to: $OUTPUT_FILE"
    echo "File size: $(ls -lh "$OUTPUT_FILE" | awk '{print $5}')"
else
    echo "Error: Failed to download schema structure"
    exit 1
fi
