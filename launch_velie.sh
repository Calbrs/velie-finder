#!/usr/bin/env bash
# ==========================================
# OCI ARM Auto-Launcher (Render/Linux) - Johannesburg
# ==========================================
set -uo pipefail

# ---- Config from env -------------------------------------------------------
COMPARTMENT_ID="${OCI_COMPARTMENT_ID:?OCI_COMPARTMENT_ID required}"
SUBNET_ID="${OCI_SUBNET_ID:?OCI_SUBNET_ID required}"
IMAGE_ID="${OCI_IMAGE_ID:?OCI_IMAGE_ID required}"
AVAILABILITY_DOMAIN="${OCI_AD:-PNQu:AF-JOHANNESBURG-1-AD-1}"
INSTANCE_NAME="${OCI_INSTANCE_NAME:-Velie}"
OCPUS="${OCI_OCPUS:-1}"
MEMORY_GB="${OCI_MEMORY_GB:-4}"

# OCI CLI auth via env.
export OCI_CLI_TENANCY="${OCI_CLI_TENANCY:?OCI_CLI_TENANCY required}"
export OCI_CLI_USER="${OCI_CLI_USER:?OCI_CLI_USER required}"
export OCI_CLI_FINGERPRINT="${OCI_CLI_FINGERPRINT:?OCI_CLI_FINGERPRINT required}"
export OCI_CLI_REGION="${OCI_CLI_REGION:-af-johannesburg-1}"

# SSH public key -> temp file.
SSH_KEY_FILE=/tmp/velie_ssh_key.pub
printf '%s\n' "${OCI_SSH_PUBLIC_KEY:?OCI_SSH_PUBLIC_KEY required}" > "$SSH_KEY_FILE"

# API signing private key (single-line with \n escapes) -> temp PEM.
API_KEY_FILE=/tmp/velie_api_key.pem
printf '%b\n' "${OCI_API_KEY:?OCI_API_KEY required}" > "$API_KEY_FILE"
chmod 600 "$API_KEY_FILE"
export OCI_CLI_KEY_FILE="$API_KEY_FILE"

# Shape config for A1.Flex.
SHAPE_CONFIG=/tmp/shape-config.json
printf '{"ocpus":%s,"memory_in_gbs":%s}\n' "$OCPUS" "$MEMORY_GB" > "$SHAPE_CONFIG"

log() { echo "[$(date -u '+%H:%M:%S')] $*"; }

log "=== SCRIPT STARTED ==="
log "Compartment: $COMPARTMENT_ID"
log "AD: $AVAILABILITY_DOMAIN | Shape: VM.Standard.A1.Flex (${OCPUS}O/${MEMORY_GB}G)"

# Guard: detect existing RUNNING/PROVISIONING instance across restarts.
instance_running() {
  oci compute instance list \
    --compartment-id "$COMPARTMENT_ID" \
    --display-name "$INSTANCE_NAME" \
    --query 'data[?"lifecycle-state"==`RUNNING` || "lifecycle-state"==`PROVISIONING` || "lifecycle-state"==`STARTING`]' \
    --raw-output 2>/dev/null | grep -q 'oci1\.instance' || return 1
}

attempt=0
while true; do
  attempt=$((attempt + 1))
  timestamp=$(date -u '+%H:%M:%S')

  log "[$timestamp] Heartbeat - loop alive, jaribio #$attempt"

  if instance_running; then
    log "[$timestamp] Instance '$INSTANCE_NAME' already RUNNING/PROVISIONING. Sleeping 1h..."
    sleep 3600
    continue
  fi

  log "[$timestamp] Launching OCI ARM A1.Flex (${OCPUS}OC/${MEMORY_GB}GB) - jaribio #$attempt"

  # --foreground: send signals to entire process group (kills oci + all Python children).
  # --kill-after=15: SIGKILL 15s after SIGTERM if process still alive.
  response=$(timeout --foreground --kill-after=15 120 oci compute instance launch \
    --compartment-id "$COMPARTMENT_ID" \
    --availability-domain "$AVAILABILITY_DOMAIN" \
    --display-name "$INSTANCE_NAME" \
    --image-id "$IMAGE_ID" \
    --shape "VM.Standard.A1.Flex" \
    --shape-config "file://$SHAPE_CONFIG" \
    --subnet-id "$SUBNET_ID" \
    --assign-public-ip true \
    --ssh-authorized-keys-file "$SSH_KEY_FILE" 2>&1)
  rc=$?

  log "[$timestamp] Launch returned rc=$rc"

  if [ "$rc" -eq 0 ] && printf '%s' "$response" | grep -q '"lifecycle-state": *"\(RUNNING\|PROVISIONING\)"'; then
    log "[$timestamp] SUCCESS - ARM instance created (jaribio #$attempt)"
    printf '%s' "$response" | head -20
    while true; do sleep 3600; done
  elif [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    log "[$timestamp] TIMEOUT/KILLED (rc=$rc) - jaribio #$attempt. Retrying in 20s..."
    sleep 20
  elif printf '%s' "$response" | grep -qiE 'capacity|InternalError'; then
    log "[$timestamp] Out of capacity - jaribio #$attempt. Retrying in 35s..."
    sleep $((30 + RANDOM % 10))
  elif printf '%s' "$response" | grep -qiE 'TooManyRequests|429'; then
    backoff=$((60 + attempt * 5))
    [ $backoff -gt 180 ] && backoff=180
    log "[$timestamp] Rate limited - jaribio #$attempt. Sleeping ${backoff}s..."
    sleep "$backoff"
  else
    log "[$timestamp] UNKNOWN ERROR - jaribio #$attempt:"
    printf '%s' "$response" | tail -10
    sleep 45
  fi
done