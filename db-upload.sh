#!/bin/bash

# Postgres Data Upload Script

# Check required environment variables
if [ -z "$JDBC_URL" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ] || [ -z "$DUMP_FILE" ]; then
    echo "Error: Missing required environment variables"
    echo "Required: JDBC_URL, DB_USER, DB_PASSWORD, DUMP_FILE"
    echo "Optional: PG_VERSION"
    echo "Usage: JDBC_URL=\"jdbc:postgresql://host:port/database\" DB_USER=<user> DB_PASSWORD=<password> DUMP_FILE=<file.dump> $0"
    exit 1
fi

# Check if dump file exists
if [ ! -f "$DUMP_FILE" ]; then
    echo "Error: Dump file not found: $DUMP_FILE"
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

echo "Uploading data from '$DUMP_FILE' to database '$DB_NAME' at $DB_HOST:$DB_PORT..."
echo "File size: $(ls -lh "$DUMP_FILE" | awk '{print $5}')"
echo "Using Postgres ${PG_VERSION} Docker image..."

# Get absolute path of dump file for Docker volume mounting
DUMP_FILE_ABS="$(realpath "$DUMP_FILE")"
DUMP_FILE_DIR="$(dirname "$DUMP_FILE_ABS")"
DUMP_FILE_NAME="$(basename "$DUMP_FILE_ABS")"

# Optional: skip errors mode
SKIP_ERRORS="${SKIP_ERRORS:-false}"

if [ "$SKIP_ERRORS" = "true" ]; then
    echo "WARNING: Skipping errors during restore (data integrity not guaranteed)"
    ERROR_OPTIONS=""
else
    ERROR_OPTIONS="--exit-on-error"
fi

# Optional: single table restore
if [ -n "$TABLE_NAME" ]; then
    echo "Restoring only table: $TABLE_NAME"
    TABLE_OPTIONS="--table=$TABLE_NAME"
else
    TABLE_OPTIONS=""
fi

# Optional: exclude specific tables
if [ -n "$EXCLUDE_TABLE" ]; then
    echo "Excluding table: $EXCLUDE_TABLE"
    EXCLUDE_OPTIONS="--exclude-table=$EXCLUDE_TABLE"
else
    EXCLUDE_OPTIONS=""
fi

# Use Docker with Postgres image for pg_restore
docker run --rm \
    $DOCKER_EXTRA_ARGS \
    -e PGPASSWORD="$DB_PASSWORD" \
    -v "$DUMP_FILE_DIR:/input:ro" \
    "postgres:${PG_VERSION}" \
    pg_restore \
    -h "$DOCKER_HOST" \
    -p "$DB_PORT" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -v \
    --data-only \
    --no-owner \
    --no-privileges \
    --disable-triggers \
    $ERROR_OPTIONS \
    $TABLE_OPTIONS \
    $EXCLUDE_OPTIONS \
    "/input/$DUMP_FILE_NAME"

# Check if pg_restore was successful
if [ $? -eq 0 ]; then
    echo "Data successfully uploaded to database '$DB_NAME'"
else
    echo "Error: Failed to upload data"
    exit 1
fi
