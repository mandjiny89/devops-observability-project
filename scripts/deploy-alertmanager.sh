
#!/usr/bin/env bash
set -euo pipefail
set +x

REGION="eu-west-2"
SECRET_NAME="project2/alertmanager/webhook-secret"

CONFIG_DIR="/opt/observability/alertmanager"
SECRETS_DIR="$CONFIG_DIR/secrets"
CONFIG="$CONFIG_DIR/alertmanager.yml"
STAGED="$CONFIG_DIR/alertmanager.yml.new"
BACKUP="$CONFIG_DIR/alertmanager.yml.bak"
IMAGE="prom/alertmanager:v0.28.1"

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

# Retrieve the password directly on EC2.
# Never print the secret.
aws secretsmanager get-secret-value \
  --region "$REGION" \
  --secret-id "$SECRET_NAME" \
  --query SecretString \
  --output text > "$SECRETS_DIR/webhook_password"

test -s "$SECRETS_DIR/webhook_password"

chown -R 65534:65534 "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"
chmod 600 "$SECRETS_DIR/webhook_password"

# Confirm the staged configuration exists.
test -s "$STAGED"

# Validate before modifying the active configuration.
docker run --rm \
  -v "$STAGED:/etc/alertmanager/alertmanager.yml:ro" \
  -v "$SECRETS_DIR:/etc/alertmanager/secrets:ro" \
  --entrypoint /bin/amtool \
  "$IMAGE" \
  check-config /etc/alertmanager/alertmanager.yml

# Back up the existing configuration.
cp "$CONFIG" "$BACKUP"

start_alertmanager() {
  docker rm -f alertmanager >/dev/null 2>&1 || true

  docker run -d \
    --name alertmanager \
    --restart unless-stopped \
    --network host \
    -v "$CONFIG:/etc/alertmanager/alertmanager.yml:ro" \
    -v "$SECRETS_DIR:/etc/alertmanager/secrets:ro" \
    -v /opt/observability/alertmanager-data:/alertmanager \
    "$IMAGE" \
    --config.file=/etc/alertmanager/alertmanager.yml \
    --storage.path=/alertmanager
}

wait_ready() {
  for i in $(seq 1 15); do
    if curl --fail --silent \
      http://127.0.0.1:9093/-/ready >/dev/null; then
      return 0
    fi
    sleep 2
  done
  return 1
}

# Install the validated configuration.
mv "$STAGED" "$CONFIG"

echo "Starting Alertmanager with new configuration."
start_alertmanager

if ! wait_ready; then
  echo "New Alertmanager failed readiness check. Rolling back."

  # Restore the previous configuration.
  cp "$BACKUP" "$CONFIG"

  start_alertmanager

  if wait_ready; then
    echo "Rollback completed. Previous configuration restored."
  else
    echo "ERROR: Rollback also failed."
  fi

  exit 1
fi

echo "Alertmanager deployment completed successfully."

