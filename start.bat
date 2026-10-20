@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title Eaglercraft Server Publisher

echo ==========================================
echo   Eaglercraft Server Publisher
echo ==========================================
echo.

REM ---- .env を読み込む ----
if exist ".env" (
  for /f "usebackq eol=# tokens=1,* delims==" %%A in (".env") do (
    if not "%%~A"=="" set "%%~A=%%~B"
  )
)

REM ---- GITHUB_TOKEN チェック ----
if "%GITHUB_TOKEN%"=="" (
  echo GITHUB_TOKEN が .env に設定されていません。
  set /p "GITHUB_TOKEN=GitHub トークン ^(ghp_...^) を貼り付けて Enter: "
  if "%GITHUB_TOKEN%"=="" (
    echo トークンが入力されませんでした。
    pause
    exit /b 1
  )
  echo.
  echo 次回からは .env に  GITHUB_TOKEN=...  を書いておくと聞かれません。
  echo.
)

REM ---- Node.js チェック ----
where node >nul 2>nul
if errorlevel 1 (
  echo node が見つかりません。Node.js をインストールしてください。
  pause
  exit /b 1
)

REM ---- cloudflared チェック ----
if /i not "%CLOUDFLARED_PATH%"=="cloudflared" (
  if not exist "%CLOUDFLARED_PATH%" (
    echo cloudflared が見つかりません: %CLOUDFLARED_PATH%
    pause
    exit /b 1
  )
) else (
  where cloudflared >nul 2>nul
  if errorlevel 1 (
    echo cloudflared が見つかりません。PATH を確認するか .env の CLOUDFLARED_PATH を設定してください。
    pause
    exit /b 1
  )
)

echo トンネルを開始します。このウィンドウは開いたままにしてください。
echo 停止するには Ctrl+C を押してください。
echo.

node scripts\update-gist.js
set "CODE=%ERRORLEVEL%"

echo.
if not "%CODE%"=="0" echo 終了コード: %CODE%
echo トンネルを終了しました。
pause
