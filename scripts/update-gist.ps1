# cloudflared URL を Gist に自動登録する (Windows PowerShell用)
param(
  [string]$Port = "8080",
  [string]$GistId = $env:GIST_ID,
  [string]$Token = $env:GITHUB_TOKEN,
  [string]$FileName = "cloudflared-url.json"
)

if ([string]::IsNullOrWhiteSpace($GistId) -or [string]::IsNullOrWhiteSpace($Token) -or $GistId -eq "YOUR_GIST_ID") {
  Write-Error 'GIST_ID と GITHUB_TOKEN が必要です。例: $env:GIST_ID="xxx"; $env:GITHUB_TOKEN="ghp_yyy"; .\scripts\update-gist.ps1'
  exit 1
}

Write-Host "cloudflared tunnel --url http://localhost:$Port を起動します..." -ForegroundColor Cyan

$currentUrl = $null

# cloudflared は進捗を stderr に出すため 2>&1 で結合してパースする
& cloudflared tunnel --url "http://localhost:$Port" 2>&1 | ForEach-Object {
  $line = $_.ToString()
  Write-Host $line
  if ($line -match 'https://[a-z0-9-]+\.trycloudflare\.com') {
    $url = $Matches[0]
    if ($url -ne $currentUrl) {
      $currentUrl = $url
      Write-Host "`n[検出] $url" -ForegroundColor Green

      $payload = @{
        files = @{
          "$FileName" = @{
            content = (@{
              url       = $url
              updatedAt = (Get-Date).ToUniversalTime().ToString("o")
              port      = [int]$Port
            } | ConvertTo-Json -Compress)
          }
        }
      } | ConvertTo-Json -Depth 5

      try {
        Invoke-RestMethod -Uri "https://api.github.com/gists/$GistId" `
          -Method Patch `
          -Headers @{ Authorization = "Bearer $Token"; Accept = "application/vnd.github+json" } `
          -Body $payload -ContentType "application/json" | Out-Null
        Write-Host "[OK] Gist更新: $url" -ForegroundColor Green
      } catch {
        Write-Host "[ERR] Gist更新失敗: $_" -ForegroundColor Red
      }
    }
  }
}
