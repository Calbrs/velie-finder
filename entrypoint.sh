#!/usr/bin/env bash
# Runs the tiny health server (keeps the Render web service warm via cron pings)
# and the OCI ARM launcher loop in the same container.
set -euo pipefail

# Health server in the background on $PORT (Render injects PORT).
python /app/health.py &

# Launcher loop in the foreground (keeps the container alive).
exec /app/launch_velie.sh