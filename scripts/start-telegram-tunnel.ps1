<#
.SYNOPSIS
  Levanta (o reemplaza) el tunel de Cloudflare hacia n8n, actualiza .env con la
  URL publica nueva y reinicia el contenedor de n8n para que quede activa.

.DESCRIPTION
  Pensado para el bot de Telegram del Modulo 9 (TF-BOT-00), que necesita una
  URL HTTPS publica real para que Telegram pueda entregarle los mensajes.
  Usa el "quick tunnel" gratuito de cloudflared (sin cuenta, sin dominio), asi
  que la URL cambia cada vez que este script se ejecuta. El tunel queda
  corriendo en segundo plano (no necesitas dejar ninguna ventana abierta).

.EXAMPLE
  .\scripts\start-telegram-tunnel.ps1
#>

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $projectRoot '.env'
$logPath = Join-Path $env:TEMP 'talentflow-tunnel.log'
$errLogPath = Join-Path $env:TEMP 'talentflow-tunnel-err.log'
$pidPath = Join-Path $env:TEMP 'talentflow-tunnel.pid'

Write-Host "== TalentFlow: activar tunel del bot de Telegram ==" -ForegroundColor Cyan

if (-not (Test-Path $envPath)) {
    throw "No encontre .env en $projectRoot. Corre este script desde el repo del proyecto (scripts\start-telegram-tunnel.ps1)."
}

# --- 1) Ubicar cloudflared ------------------------------------------------
$cloudflared = Get-Command cloudflared -ErrorAction SilentlyContinue
if (-not $cloudflared) {
    $candidate = "C:\Program Files (x86)\cloudflared\cloudflared.exe"
    if (Test-Path $candidate) {
        $cloudflaredPath = $candidate
    } else {
        throw "No encontre cloudflared. Instalalo con: winget install --id Cloudflare.cloudflared --accept-package-agreements --accept-source-agreements"
    }
} else {
    $cloudflaredPath = $cloudflared.Source
}

# --- 2) Leer el puerto local de n8n desde .env ----------------------------
$envLines = Get-Content $envPath
$hostPortLine = $envLines | Where-Object { $_ -match '^N8N_HOST_PORT=' } | Select-Object -First 1
if ($hostPortLine) {
    $n8nPort = ($hostPortLine -split '=', 2)[1].Trim()
} else {
    $n8nPort = '5678'
}
Write-Host "Puerto local de n8n: $n8nPort"

# --- 3) Detener cualquier tunel anterior ----------------------------------
$previousPid = $null
if (Test-Path $pidPath) {
    $previousPid = Get-Content $pidPath -ErrorAction SilentlyContinue
}
if ($previousPid) {
    $existing = Get-Process -Id $previousPid -ErrorAction SilentlyContinue
    if ($existing -and $existing.ProcessName -eq 'cloudflared') {
        Write-Host "Deteniendo tunel anterior (PID $previousPid)..."
        Stop-Process -Id $previousPid -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
}
Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

# --- 4) Levantar el tunel nuevo -------------------------------------------
Remove-Item $logPath, $errLogPath -ErrorAction SilentlyContinue

Write-Host "Levantando tunel hacia http://localhost:$n8nPort ..."
$proc = Start-Process -FilePath $cloudflaredPath `
    -ArgumentList "tunnel", "--url", "http://localhost:$n8nPort" `
    -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $logPath -RedirectStandardError $errLogPath

$proc.Id | Out-File -FilePath $pidPath -Encoding ascii -Force

# --- 5) Esperar a que aparezca la URL publica en el log -------------------
$publicUrl = $null
$deadline = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $deadline -and -not $publicUrl) {
    Start-Sleep -Seconds 1
    $content = Get-Content $errLogPath -ErrorAction SilentlyContinue
    $match = $content | Select-String -Pattern 'https://[a-zA-Z0-9\-]+\.trycloudflare\.com' | Select-Object -First 1
    if ($match) {
        $publicUrl = $match.Matches[0].Value
    }
}

if (-not $publicUrl) {
    Write-Host "No logre leer la URL del tunel a tiempo. Revisa el log:" -ForegroundColor Yellow
    Write-Host $errLogPath
    throw "Fallo obteniendo la URL publica de cloudflared."
}

Write-Host "URL publica: $publicUrl" -ForegroundColor Green
$hostOnly = $publicUrl -replace '^https://', ''

# --- 6) Actualizar .env -----------------------------------------------------
Write-Host "Actualizando .env ..."
$updated = $envLines | ForEach-Object {
    if ($_ -match '^N8N_HOST=') { "N8N_HOST=$hostOnly" }
    elseif ($_ -match '^N8N_PROTOCOL=') { "N8N_PROTOCOL=https" }
    elseif ($_ -match '^WEBHOOK_URL=') { "WEBHOOK_URL=$publicUrl" }
    else { $_ }
}
Set-Content -Path $envPath -Value $updated -Encoding utf8

# --- 7) Reiniciar n8n con la URL nueva --------------------------------------
Write-Host "Reiniciando n8n ..."
Push-Location $projectRoot
try {
    docker compose up -d n8n | Out-Null

    $healthy = $false
    $healthDeadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $healthDeadline -and -not $healthy) {
        Start-Sleep -Seconds 3
        $status = docker compose ps n8n --format json 2>$null | ConvertFrom-Json
        if ($status -and $status.Health -eq 'healthy') { $healthy = $true }
    }
} finally {
    Pop-Location
}

if (-not $healthy) {
    Write-Host "n8n todavia no reporta 'healthy'. Puede que necesite unos segundos mas; revisa con 'docker compose ps'." -ForegroundColor Yellow
} else {
    Write-Host "n8n esta arriba y sano." -ForegroundColor Green
}

Write-Host ""
Write-Host "== Listo ==" -ForegroundColor Cyan
Write-Host "Tunel activo (PID $($proc.Id)), corriendo en segundo plano."
Write-Host "URL publica: $publicUrl"
Write-Host "n8n local:   http://localhost:$n8nPort"
Write-Host ""
Write-Host "Siguiente paso: entra a n8n, abre 'TF-BOT-00 Telegram Assistant RRHH' y dale Publish"
Write-Host "(si ya estaba publicado, Telegram ya deberia estar usando la URL nueva sin nada mas que hacer)."
Write-Host ""
Write-Host "Para detener el tunel mas tarde: Stop-Process -Id $($proc.Id)"
