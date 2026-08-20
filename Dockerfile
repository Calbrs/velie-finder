# Render-ready Docker image for the OCI ARM auto-launcher.
# Runs the retry loop 24/7 from a Render background worker.
FROM python:3.12-slim

# OCI CLI needs git + openssh-client for ssh-related commands.
RUN apt-get update \
  && apt-get install -y --no-install-recommends git openssh-client \
  && rm -rf /var/lib/apt/lists/* \
  && pip install --no-cache-dir oci-cli

WORKDIR /app
COPY launch_velie.sh /app/launch_velie.sh
RUN chmod +x /app/launch_velie.sh

CMD ["/app/launch_velie.sh"]