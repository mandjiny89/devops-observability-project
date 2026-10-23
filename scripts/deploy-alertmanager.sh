
#!/usr/bin/env bash
set -euo pipefail

REGION="eu-west-2"
SECRET_NAME="project2/alertmanager/webhook-secret"

CONFIG_DIR="/opt/observability/alertmanager"
SECRETS_DIR="$CONFIG_DIR/secrets"

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

# Retrieve password without printing it.
set +x
aws secretsmanager get-secret-value \
  --region "$REGION" \
  --secret-id "$SECRET_NAME" \
  --query SecretString \
  --output text > "$SECRETS_DIR/webhook_password"

chmod 600 "$SECRETS_DIR/webhook_password"

# Alertmanager normally runs as a non-root user.
chown -R 65534:65534 "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

# Validate the staged configuration before replacing the active one.
docker run --rm \
  -v "$CONFIG_DIR/alertmanager.yml.new:/etc/alertmanager/alertmanager.yml:ro" \
  -v "$SECRETS_DIR:/etc/alertmanager/secrets:ro" \
  --entrypoint /bin/amtool \
  prom/alertmanager:v0.28.1 \
  check-config /etc/alertmanager/alertmanager.yml

# Back up the existing configuration and install the validated one.
cp "$CONFIG_DIR/alertmanager.yml" "$CONFIG_DIR/alertmanager.yml.bak"
mv "$CONFIG_DIR/alertmanager.yml.new" "$CONFIG_DIR/alertmanager.yml"

# Validate configuration before restarting.
docker run --rm \
  -v "$CONFIG_DIR/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro" \
  -v "$SECRETS_DIR:/etc/alertmanager/secrets:ro" \
  --entrypoint /bin/amtool \
  prom/alertmanager:v0.28.1 \
  check-config /etc/alertmanager/alertmanager.yml

# Replace only the Alertmanager container.
docker rm -f alertmanager || true

docker run -d \
  --name alertmanager \
  --restart unless-stopped \
  --network host \
  -v "$CONFIG_DIR/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro" \
  -v "$SECRETS_DIR:/etc/alertmanager/secrets:ro" \
  -v /opt/observability/alertmanager-data:/alertmanager \
  prom/alertmanager:v0.28.1 \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/alertmanager

# Wait for Alertmanager to become healthy.
healthy=false

for i in $(seq 1 15); do
  if curl --fail --silent \
    http://127.0.0.1:9093/-/ready >/dev/null; then
    healthy=true
    break
  fi

  sleep 2
done

if [ "$healthy" != "true" ]; then
  echo "ERROR: Alertmanager did not become ready."
  docker logs --tail 30 alertmanager
  exit 1
fi

echo "Alertmanager deployment completed."

