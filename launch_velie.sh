#!/usr/bin/env bash
# ==========================================
# OCI ARM Auto-Launcher (Render/Linux) - Johannesburg
# ==========================================
# Runs forever on a Render background worker, retrying VM.Standard.A1.Flex
# launch until Oracle has capacity. All credentials come from environment
# variables (Render secrets) - nothing sensitive is committed.
set -uo pipefail

# ---- Config from env (Render secrets / env vars) ---------------------------
COMPARTMENT_ID="${OCI_COMPARTMENT_ID:?OCI_COMPARTMENT_ID required}"
SUBNET_ID="${OCI_SUBNET_ID:?OCI_SUBNET_ID required}"
IMAGE_ID="${OCI_IMAGE_ID:?OCI_IMAGE_ID required}"
AVAILABILITY_DOMAIN="${OCI_AD:-PNQu:AF-JOHANNESBURG-1-AD-1}"
INSTANCE_NAME="${OCI_INSTANCE_NAME:-Velie}"
OCPUS="${OCI_OCPUS:-1}"
MEMORY_GB="${OCI_MEMORY_GB:-4}"

# OCI CLI auth via env (Render secret) - private key is NEVER written to repo.
export OCI_CLI_TENANCY="${OCI_CLI_TENANCY:?OCI_CLI_TENANCY required}"
export OCI_CLI_USER="${OCI_CLI_USER:?OCI_CLI_USER required}"
export OCI_CLI_FINGERPRINT="${OCI_CLI_FINGERPRINT:?OCI_CLI_FINGERPRINT required}"
export OCI_CLI_REGION="${OCI_CLI_REGION:-af-johannesburg-1}"

# SSH public key (content, from env). Render has no filesystem, so write it out.
SSH_KEY_FILE=/tmp/velie_ssh_key.pub
printf '%s\n' "${OCI_SSH_PUBLIC_KEY:?OCI_SSH_PUBLIC_KEY required}" > "$SSH_KEY_FILE"

# API signing private key (single-line with \n escapes, from env secret) ->
# decoded into a temp PEM file for the CLI.
API_KEY_FILE=/tmp/velie_api_key.pem
printf '%b\n' "${OCI_API_KEY:?OCI_API_KEY required}" > "$API_KEY_FILE"
chmod 600 "$API_KEY_FILE"
export OCI_CLI_KEY_FILE="$API_KEY_FILE"

# shape-config: create the JSON file OCI CLI wants as a file:// reference.
SHAPE_CONFIG=/tmp/shape-config.json
printf '{"ocpus":%s,"memory_in_gbs":%s}\n' "$OCPUS" "$MEMORY_GB" > "$SHAPE_CONFIG"

log() { echo "[$(date -u '+%H:%M:%S')] $*"; }

# Guard against creating duplicate instances across restarts.
instance_running() {
  timeout 60 oci compute instance list \
    --compartment-id "$COMPARTMENT_ID" \
    --display-name "$INSTANCE_NAME" \
    --query 'data[?"lifecycle-state"==`RUNNING` || "lifecycle-state"==`PROVISIONING` || "lifecycle-state"==`STARTING`]' \
    --raw-output 2>/dev/null | grep -q 'oci1\.instance' || return 1
}

attempt=0
while true; do
  attempt=$((attempt + 1))
  timestamp=$(date -u '+%H:%M:%S')

  if instance_running; then
    log "[$timestamp] Instancesi '$INSTANCE_NAME' tayari RUNNING/PROVISIONING. Inapumzika 1h..."
    sleep 3600
    continue
  fi

  log "[$timestamp] Inajaribu kutengeneza ARM A1.Flex (${OCPUS} OCPU, ${MEMORY_GB}GB) - jaribio #$attempt"

  response=$(timeout 120 oci compute instance launch \
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

  if [ "$rc" -eq 0 ] && printf '%s' "$response" | grep -q '"lifecycle-state": *"\(RUNNING\|PROVISIONING\)"'; then
    log "🎉 IMETENGENEZWA! ARM server ipo tayari (jaribio #$attempt)"
    echo "$response"
    # Keep the worker alive + healthy; instance exists so just wait.
    while true; do sleep 3600; done
  elif [ "$rc" -eq 124 ]; then
    log "[$timestamp] Muongo wa API ulichukua muda mrefu (>120s) - jaribio #$attempt. Inajaribu tena..."
    sleep $((15 + RANDOM % 10))
  elif printf '%s' "$response" | grep -qiE 'capacity|InternalError'; then
    log "[$timestamp] Out of capacity (jaribio #$attempt). Inajaribu tena..."
    sleep $((30 + RANDOM % 10))
  elif printf '%s' "$response" | grep -qiE 'TooManyRequests|429'; then
    backoff=$((60 + attempt * 5))
    [ $backoff -gt 180 ] && backoff=180
    log "[$timestamp] Rate limited (jaribio #$attempt). Inapumzika ${backoff}s..."
    sleep "$backoff"
  else
    log "[$timestamp] Error au response nyingine (jaribio #$attempt):"
    echo "$response" | tail -5
    sleep 45
  fi
done