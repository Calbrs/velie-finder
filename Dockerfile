# Render-ready Docker image for the OCI ARM auto-launcher.
# Runs as a web service: a tiny /health server (kept warm by cron pings) plus
# the 24/7 retry loop.
FROM python:3.12-slim

# OCI CLI needs git + openssh-client for ssh-related commands.
RUN apt-get update \
  && apt-get install -y --no-install-recommends git openssh-client coreutils \
  && rm -rf /var/lib/apt/lists/* \
  && pip install --no-cache-dir oci-cli

WORKDIR /app
COPY launch_velie.sh /app/launch_velie.sh
COPY launch_helper.py /app/launch_helper.py
COPY health.py /app/health.py
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/launch_velie.sh /app/entrypoint.sh

EXPOSE 10000
CMD ["/app/entrypoint.sh"]