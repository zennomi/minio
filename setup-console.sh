#!/bin/bash

# MinIO Console Setup Script
# This script automatically sets up the console user and admin policy for MinIO

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
# Use MINIO_HOST if running in Docker, otherwise localhost
MINIO_HOST="${MINIO_HOST:-localhost}"
MINIO_ENDPOINT="${MINIO_ENDPOINT:-http://${MINIO_HOST}:9000}"
MINIO_ROOT_USER="${MINIO_ROOT_USER:-minioadmin}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-minioadmin}"
CONSOLE_USER="${CONSOLE_USER:-console}"
# Generate password if not set (use a method that works in containers)
if [ -z "${CONSOLE_PASSWORD}" ]; then
    if command -v openssl &> /dev/null; then
        CONSOLE_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-32)
    elif [ -c /dev/urandom ]; then
        CONSOLE_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 32)
    else
        CONSOLE_PASSWORD=$(date +%s | sha256sum | base64 | head -c 32)
    fi
fi
ALIAS_NAME="${ALIAS_NAME:-myminio}"
POLICY_NAME="${POLICY_NAME:-consoleAdmin}"

echo -e "${GREEN}MinIO Console Setup Script${NC}"
echo "================================"
echo ""

# Check if mc (MinIO Client) is installed
if ! command -v mc &> /dev/null; then
    echo -e "${RED}Error: MinIO Client (mc) is not installed.${NC}"
    echo "Please install it from: https://min.io/docs/minio/linux/reference/minio-mc.html#install-mc"
    exit 1
fi

echo -e "${YELLOW}Waiting for MinIO server to be ready...${NC}"
# Wait for MinIO to be ready (max 120 seconds)
MAX_RETRIES=60
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    # Try to connect using mc (works better in Docker)
    if mc alias list "${ALIAS_NAME}" > /dev/null 2>&1 || \
       (mc alias set "${ALIAS_NAME}" "${MINIO_ENDPOINT}" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" > /dev/null 2>&1 && \
        mc admin info "${ALIAS_NAME}" > /dev/null 2>&1); then
        echo -e "${GREEN}MinIO server is ready!${NC}"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo -n "."
    sleep 2
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo -e "\n${RED}Error: MinIO server did not become ready in time.${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}Configuring MinIO client alias...${NC}"
# Remove existing alias if it exists
mc alias remove "${ALIAS_NAME}" 2>/dev/null || true
# Set up alias
if ! mc alias set "${ALIAS_NAME}" "${MINIO_ENDPOINT}" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}"; then
    echo -e "${RED}Error: Failed to configure MinIO client alias.${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}Checking if console user already exists...${NC}"
# Check if user already exists
USER_EXISTS=false
if mc admin user info "${ALIAS_NAME}" "${CONSOLE_USER}" > /dev/null 2>&1; then
    USER_EXISTS=true
    echo -e "${GREEN}Console user '${CONSOLE_USER}' already exists. Skipping user creation.${NC}"
else
    echo -e "${YELLOW}Creating console user '${CONSOLE_USER}'...${NC}"
    if echo "${CONSOLE_PASSWORD}" | mc admin user add "${ALIAS_NAME}" "${CONSOLE_USER}"; then
        echo -e "${GREEN}Console user created successfully!${NC}"
        USER_EXISTS=true
    else
        echo -e "${RED}Error: Failed to create console user.${NC}"
        exit 1
    fi
fi

if [ "$USER_EXISTS" = true ] && [ -n "${CONSOLE_PASSWORD}" ]; then
    echo -e "${YELLOW}Console user password: ${CONSOLE_PASSWORD}${NC}"
    echo -e "${YELLOW}⚠️  Please save this password securely!${NC}"
fi

echo ""
echo -e "${YELLOW}Creating admin policy...${NC}"
# Create policy JSON file
POLICY_FILE=$(mktemp)
cat > "${POLICY_FILE}" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "admin:*"
      ],
      "Effect": "Allow",
      "Sid": ""
    },
    {
      "Action": [
        "s3:*"
      ],
      "Effect": "Allow",
      "Resource": [
        "arn:aws:s3:::*"
      ],
      "Sid": ""
    }
  ]
}
EOF

# Check if policy already exists
POLICY_EXISTS=false
if mc admin policy info "${ALIAS_NAME}" "${POLICY_NAME}" > /dev/null 2>&1; then
    POLICY_EXISTS=true
    echo -e "${GREEN}Policy '${POLICY_NAME}' already exists.${NC}"
else
    echo -e "${YELLOW}Creating policy '${POLICY_NAME}'...${NC}"
    if ! mc admin policy create "${ALIAS_NAME}" "${POLICY_NAME}" "${POLICY_FILE}"; then
        echo -e "${RED}Error: Failed to create policy.${NC}"
        rm -f "${POLICY_FILE}"
        exit 1
    fi
fi

# Clean up temp file
rm -f "${POLICY_FILE}"

echo ""
echo -e "${YELLOW}Attaching policy to console user...${NC}"
# Attach policy to user (this will fail silently if already attached)
mc admin policy attach "${ALIAS_NAME}" "${POLICY_NAME}" --user="${CONSOLE_USER}" || true

echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Setup completed successfully!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo "Console Admin UI: http://localhost:9090"
echo "Access Key: ${CONSOLE_USER}"
# Save password to file if running in Docker
if [ -d "/setup" ]; then
    echo "${CONSOLE_PASSWORD}" > /setup/console-password.txt
    chmod 600 /setup/console-password.txt
    echo -e "${YELLOW}Password saved to: /setup/console-password.txt${NC}"
    echo "Secret Key: ${CONSOLE_PASSWORD}"
else
    echo "Secret Key: ${CONSOLE_PASSWORD}"
fi
echo ""
echo -e "${YELLOW}⚠️  Please save the secret key above securely!${NC}"
echo ""

