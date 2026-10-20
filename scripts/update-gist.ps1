# Eaglercraft サーバー公開用: cloudflared の URL を Gist へ自動登録する (Windows PowerShell)
#
#   $env:GITHUB_TOKEN = "ghp_xxx"
#   .\scripts\update-gist.ps1
#
# 設定の優先順位: パラメータ > 環境変数 > server.config.json > 既定値
param(
  [string]$Port = "",
  [string]$GistId = $env:GIST_ID,
  [string]$Token = $env:GITHUB_TOKEN,
  [string]$FileName = "cloudflared-url.json",
  [string]$Cloudflared = $env:CLOUDFLARED_PATH,
  [string]$ServerName = $env:SERVER_NAME,
  [string]$Motd = $env:MOTD,
  [string]$Protocols = $env:PROTOCOLS,
  [int]$HeartbeatSeconds = 300,
  [int]$ReadyTimeoutSeconds = 30
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
$ConfigFile = Join-Path $Root "server.config.json"

# ===== server.config.json を読み込む =====
$FileCfg = @{}
if (Test-Path $ConfigFile) {
  try {
    $FileCfg = Get-Content -Path $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
  } catch {
    Write-Warning "$ConfigFile を読み込めませんでした: $_"
  }
}

function Pick-Value {
  param([object]$Param, [object]$Env, [object]$File, [object]$Default)
  if ($null -ne $Param -and "$Param" -ne "") { return $Param }
  if ($null -ne $Env -and "$Env" -ne "") { return $Env }
  if ($null -ne $File -and "$File" -ne "") { return $File }
  return $Default
}

$Port = [int](Pick-Value $Port $env:PORT $FileCfg.port 25565)
$GistId = Pick-Value $GistId $env:GIST_ID $FileCfg.gistId "ace74a8eec7a4f2ad49aa11c7e222412"
$Cloudflared = Pick-Value $Cloudflared $env:CLOUDFLARED_PATH $FileCfg.cloudflared "cloudflared"
$ServerName = Pick-Value $ServerName $env:SERVER_NAME $FileCfg.serverName "Eaglercraft Server"
$Motd = Pick-Value $Motd $env:MOTD $FileCfg.motd ""
$Protocols = Pick-Value $Protocols $env:PROTOCOLS $FileCfg.protocols "1.5 / 1.8 / 1.12"

if ([string]::IsNullOrWhiteSpace($Token)) {
  Write-Error 'GITHUB_TOKEN が必要です。例: $env:GITHUB_TOKEN="ghp_xxx"; .\scripts\update-gist.ps1'
  exit 1
}
if ([string]::IsNullOrWhiteSpace($GistId) -or $GistId -eq "YOUR_GIST_ID") {
  Write-Error 'GIST_ID が必要です。'
  exit 1
}

# ===== Gist 書き込み =====
$script:CurrentUrl = $null

function Get-GistState {
  $hostName = $null
  if ($script:CurrentUrl) {
    try { $hostName = ([System.Uri]$script:CurrentUrl).Authority } catch { $hostName = $null }
  }
  $ordered = [ordered]@{
    url       = $script:CurrentUrl
    host      = $hostName
    port      = $Port
    updatedAt = (Get-Date).ToUniversalTime().ToString("o")
    serverName = $ServerName
    motd      = $Motd
    protocols = $Protocols
    online    = [bool]$script:CurrentUrl
  }
  return $ordered
}

function Write-GistState {
  $payload = @{
    files = @{
      $FileName = @{
        content = (Get-GistState | ConvertTo-Json -Depth 5)
      }
    }
  } | ConvertTo-Json -Depth 6

  try {
    Invoke-RestMethod -Uri "https://api.github.com/gists/$GistId" `
      -Method Patch `
      -Headers @{ Authorization = "Bearer $Token"; Accept = "application/vnd.github+json" } `
      -Body $payload -ContentType "application/json" | Out-Null
    if ($script:CurrentUrl) {
      Write-Host "[OK] Gist更新: $script:CurrentUrl" -ForegroundColor Green
    } else {
      Write-Host "[OK] Gist更新: (url をクリア)" -ForegroundColor Green
    }
  } catch {
    Write-Host "[ERR] Gist更新失敗: $_" -ForegroundColor Red
  }
}

# ===== 待受確認 =====
function Test-PortReady {
  param([int]$TargetPort, [int]$TimeoutSeconds)
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
      $client.Connect("127.0.0.1", $TargetPort)
      $client.Close()
      return $true
    } catch {
      $client.Close()
      Start-Sleep -Seconds 1
    }
  }
  return $false
}

if (-not (Test-PortReady -TargetPort $Port -TimeoutSeconds $ReadyTimeoutSeconds)) {
  Write-Error "localhost:$Port が待ち受けしていません。Eaglercraft サーバーが起動しているか確認してください。"
  exit 1
}
Write-Host "[OK] localhost:$Port の待受を確認しました" -ForegroundColor Green

# ===== cloudflared 起動 =====
$logDir = Join-Path $env:TEMP ("eagler-tunnel-" + [System.Guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$outFile = Join-Path $logDir "out.log"
$errFile = Join-Path $logDir "err.log"

Write-Host "cloudflared tunnel --url http://localhost:$Port を起動します..." -ForegroundColor Cyan
$proc = Start-Process -FilePath $Cloudflared `
  -ArgumentList @("tunnel", "--url", "http://localhost:$Port", "--no-autoupdate") `
  -RedirectStandardOutput $outFile -RedirectStandardError $errFile `
  -PassThru -NoNewWindow

$outPos = 0
$errPos = 0
$lastHeartbeat = Get-Date
$urlPattern = 'https://[a-z0-9\-\.]+\.trycloudflare\.com'

try {
  while (-not $proc.HasExited) {
    Start-Sleep -Milliseconds 800

    foreach ($file in @(@{ Path = $outFile; Pos = "outPos" }, @{ Path = $errFile; Pos = "errPos" })) {
      if (-not (Test-Path $file.Path)) { continue }
      $content = Get-Content -Path $file.Path -Raw -ErrorAction SilentlyContinue
      if (-not $content) { continue }
      $pos = (Get-Variable -Name $file.Pos -Scope Script -ValueOnly)
      if ($content.Length -le $pos) { continue }
      $new = $content.Substring($pos)
      Set-Variable -Name $file.Pos -Value $content.Length -Scope Script

      foreach ($line in ($new -split "`r?`n")) {
        if ($line.Trim() -eq "") { continue }
        Write-Host $line
        if ($line -match $urlPattern) {
          $url = $Matches[0]
          if ($url -ne $script:CurrentUrl) {
            $script:CurrentUrl = $url
            Write-Host "`n[検出] $url" -ForegroundColor Green
            Write-GistState
            $lastHeartbeat = Get-Date
          }
        }
      }
    }

    if ($script:CurrentUrl -and ((Get-Date) - $lastHeartbeat).TotalSeconds -ge $HeartbeatSeconds) {
      $lastHeartbeat = Get-Date
      Write-GistState
    }
  }

  Write-Host "cloudflared終了 (code=$($proc.ExitCode))" -ForegroundColor Yellow
  $script:CurrentUrl = $null
  Write-GistState
  exit $proc.ExitCode
}
finally {
  if ($proc -and -not $proc.HasExited) {
    # shell 経由の起動なので、プロセスツリーごと止める
    & taskkill.exe /pid $proc.Id /T /F 2>$null | Out-Null
  }
}
