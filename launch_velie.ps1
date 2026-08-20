# ==========================================
# OCI ARM Auto-Launcher Script (Johannesburg) - FIXED
# Run locally on Windows for debugging. For 24/7 use launch_velie.sh + Render.
# ==========================================
$COMPARTMENT_ID = $env:OCI_COMPARTMENT_ID
if (-not $COMPARTMENT_ID) { $COMPARTMENT_ID = "ocid1.tenancy.oc1..aaaaaaaaufavhljgkfzsg5on5diruv2y44434mu2tw4ucay6bb5l7dvwe2kq" }
$SUBNET_ID      = $env:OCI_SUBNET_ID
if (-not $SUBNET_ID) { $SUBNET_ID = "ocid1.subnet.oc1.af-johannesburg-1.aaaaaaaaumq2s6q4scq5zegp2q4kyysf4tddpvsfnrskrqffz3kzit6vamea" }
$IMAGE_ID       = $env:OCI_IMAGE_ID
if (-not $IMAGE_ID) { $IMAGE_ID = "ocid1.image.oc1.af-johannesburg-1.aaaaaaaaygiilkfrlk2nvcjfhl62d6oh3xnx7ykfmyecyrng43dhyrczgu4a" }
$AVAILABILITY_DOMAIN = if ($env:OCI_AD) { $env:OCI_AD } else { "PNQu:AF-JOHANNESBURG-1-AD-1" }
$INSTANCE_NAME  = if ($env:OCI_INSTANCE_NAME) { $env:OCI_INSTANCE_NAME } else { "Velie" }
$OCPUS          = if ($env:OCI_OCPUS) { $env:OCI_OCPUS } else { "1" }
$MEMORY_GB      = if ($env:OCI_MEMORY_GB) { $env:OCI_MEMORY_GB } else { "4" }
$SSH_KEY_PATH   = $env:OCI_SSH_PUBLIC_KEY_PATH
if (-not $SSH_KEY_PATH) { $SSH_KEY_PATH = "C:\Users\7014\Downloads\ssh-key-2026-08-11.key.pub" }
$OCI_EXE        = $env:OCI_EXE
if (-not $OCI_EXE) { $OCI_EXE = "C:\Users\7014\bin\oci.exe" }

# shape-config must be a real file for OCI CLI (file:// reference). Create it.
$shapeConfigFile = Join-Path $env:TEMP "shape-config.json"
@("{0}`"ocpus`":{1},`"memory_in_gbs`":{2}{3}" -f '{', $OCPUS, $MEMORY_GB, '}') | Set-Content -Path $shapeConfigFile -NoNewline
$shapeConfig = "file://$shapeConfigFile"

Write-Host "Inaanza kutafuta nafasi ya ARM A1.Flex (${OCPUS} OCPU, ${MEMORY_GB}GB RAM) Johannesburg..." -ForegroundColor Cyan

$attempt = 0

while ($true) {
    $attempt++
    $timestamp = Get-Date -Format "HH:mm:ss"

    # Guard: bail if an instance with this name is already RUNNING/PROVISIONING.
    $existing = & $OCI_EXE compute instance list `
        --compartment-id $COMPARTMENT_ID `
        --display-name $INSTANCE_NAME `
        --query 'data[?"lifecycle-state"==`RUNNING` || "lifecycle-state"==`PROVISIONING` || "lifecycle-state"==`STARTING`]' `
        --raw-output 2>$null
    if ($LASTEXITCODE -eq 0 -and $existing -match 'oci1\.instance') {
        Write-Host "[$timestamp] Instancesi '$INSTANCE_NAME' tayari RUNNING/PROVISIONING. Inapumzika 1h..." -ForegroundColor Green
        Start-Sleep -Seconds 3600
        continue
    }

    $ociArgs = @(
        "compute", "instance", "launch",
        "--compartment-id", $COMPARTMENT_ID,
        "--availability-domain", $AVAILABILITY_DOMAIN,
        "--display-name", $INSTANCE_NAME,
        "--image-id", $IMAGE_ID,
        "--shape", "VM.Standard.A1.Flex",
        "--shape-config", $shapeConfig,
        "--subnet-id", $SUBNET_ID,
        "--assign-public-ip", "true",
        "--ssh-authorized-keys-file", $SSH_KEY_PATH
    )

    $response = & $OCI_EXE $ociArgs 2>&1
    $exitCode = $LASTEXITCODE
    $responseText = $response -join " "

    if ($exitCode -eq 0 -and $responseText -match '"lifecycle-state":\s*"(RUNNING|PROVISIONING)"') {
        Write-Host "🎉 IMETENGENEZWA KWELI! Server yako ya ARM ipo tayari Oracle Cloud! (Jaribio #$attempt)" -ForegroundColor Green
        Write-Host $responseText
        break
    }
    elseif ($responseText -match "capacity|InternalError") {
        Write-Host "[$timestamp] Bado imejaa (Out of capacity). Jaribio #$attempt. Inajaribu tena..." -ForegroundColor Yellow
        Start-Sleep -Seconds (30 + (Get-Random -Maximum 10))
    }
    elseif ($responseText -match "TooManyRequests|429") {
        Write-Host "[$timestamp] Oracle Rate Limit (Too Many Requests). Jaribio #$attempt. Inapumzika..." -ForegroundColor DarkYellow
        $backoff = [Math]::Min(60 + ($attempt * 5), 180)
        Start-Sleep -Seconds $backoff
    }
    else {
        Write-Host "[$timestamp] Kuna Error au Response nyingine (Jaribio #$attempt):" -ForegroundColor Red
        Write-Host $responseText -ForegroundColor Gray
        Start-Sleep -Seconds 45
    }
}