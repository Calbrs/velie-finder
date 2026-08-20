# Velie Finder

24/7 OCI ARM (Ampere A1.Flex) auto-launcher. Waits for Oracle capacity in
Johannesburg and creates the free-tier `VM.Standard.A1.Flex` instance as soon as
a slot opens. Designed to run as a **Render background worker** so the retry
loop never stops.

## Why

Oracle's Always-Free Ampere ARM shapes report "Out of capacity" in the South
Africa (Johannesburg) region. Capacity fluctuates by the second as other users
delete instances, so this loop polls the OCI API until a slot frees up.

## Repo layout

- `launch_velie.sh` – Linux/bash launcher, runs on Render 24/7 (all secrets via env).
- `launch_velie.ps1` – Windows/PowerShell version, for local debugging only.
- `Dockerfile` – installs the OCI CLI; entrypoint is `launch_velie.sh`.
- `render.yaml` – Render blueprint (background worker, free plan).

## Deploy on Render

1. Push this repo to GitHub.
2. In Render → **New → Blueprint**, pick the repo. It reads `render.yaml`.
3. Set the environment variables marked `sync: false` under **Environment**:

   | Variable | What |
   |---|---|
   | `OCI_COMPARTMENT_ID` | Compartment OCID (tenancy OCID = root compartment) |
   | `OCI_SUBNET_ID` | Subnet OCID in `af-johannesburg-1` |
   | `OCI_IMAGE_ID` | ARM-capable Oracle Linux image OCID |
   | `OCI_CLI_TENANCY` | Your tenancy OCID |
   | `OCI_CLI_USER` | User OCID for the OCI API key |
   | `OCI_CLI_FINGERPRINT` | API key fingerprint |
   | `OCI_SSH_PUBLIC_KEY` | **Contents** of the public SSH key (`ssh-rsa ...`) |
   | `OCI_API_KEY` | **Contents** of the PEM private API key |

   The private API key must go in Render as a **secret** (never commit it).

4. Deploy. The worker logs each attempt; when a slot opens it prints the
   instance OCID and stays alive.

## Log messages (Swahili)

- `Out of capacity ... Inajaribu tena` → retrying, waiting 30–40s
- `Rate limited ... Inapumzika` → backing off on 429s
- `IMETENGENEZWA!` → instance created successfully 🎉