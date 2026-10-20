# Eaglercraft サーバー公開 (cloudflared + Vercel + GitHub Gist)

`cloudflared tunnel --url` が発行するランダム URL
(`https://xxx.trycloudflare.com`) は再起動のたびに変わります。
この仕組みは **Eaglercraft サーバー公開用に**、Vercel の固定 URL に
「いま接続すべきアドレス」を表示するページを用意し、
どの URL を開くべきかが常にわかります。

```
[自宅PC]  Eaglercraft サーバー (Paper + EaglercraftXServer)  ← 25565 番で HTTP / WebSocket / Minecraft
              │
              │  cloudflared tunnel --url http://localhost:25565
              ▼
[PC]  updater (scripts/update-gist.js)  →  ランダム URL を検出 → GitHub Gist へ書き換え
              │
              ▼
[Vercel] 固定URL のページ  →  Gist を読む  →  接続アドレス (Direct Connect 用) を表示
```

- DB 不要。Gist が「いまの URL の置き場所」。
- クライアント側は **Direct Connect** 方式のみ。Web クライアントの同時配信はしない。

---

## 1. 前提

| 項目 | 値 |
| --- | --- |
| Minecraft / Eaglercraft サーバー | `Eaglercraft-Server-Paper-main` (Paper 1.12.2 + `EaglerXServer.jar`) |
| 待受ポート | **25565** (Java 版・Eaglercraft 共通。HTTP / WebSocket も同居) |
| トンネル先 | `http://localhost:25565` |
| Gist | `ace74a8eec7a4f2ad49aa11c7e222412` (public, `cloudflared-url.json`) |
| GitHub リポジトリ | `bismuth47/cloudflared-redirect` (Vercel 連携先) |

> `http://localhost:25565/` を開くと 404 が出ますが、**これが正常**です。
> EaglercraftXServer の案内ページ (「この URL は WebSocket アドレスです。EaglercraftX クライアントの
> Direct Connect に入力してください」) が返るだけです。

## 2. サーバー情報を設定する

`server.config.json` を編集します。updater がこの内容を Gist に書き込み、Vercel のページに表示します。

```json
{
  "serverName": "My Eaglercraft Server",
  "motd": "&6An EaglercraftX server",
  "protocols": "1.5 / 1.8 / 1.12",
  "port": 25565
}
```

| キー | 説明 |
| --- | --- |
| `serverName` | ページに表示するサーバー名 |
| `motd` | サーバー説明。`&a` `§a` 形式のレガシーコードはカラーで表示される |
| `protocols` | 対応バージョン表示 |
| `port` | 待受ポート (既定 25565) |

環境変数 (`SERVER_NAME` / `MOTD` / `PROTOCOLS` / `PORT`) があればそちらが優先されます。

## 3. PC 側で updater を起動する

### かんたん起動 (`start.bat`)

**`start.bat` をダブルクリックするだけ**で起動できます。
設定は `.env` (Git 管理外) から読み込みます。

```ini
GIST_ID=ace74a8eec7a4f2ad49aa11c7e222412
GITHUB_TOKEN=ghp_xxx
PORT=25565
CLOUDFLARED_PATH=cloudflared
```

- `.env` が無い場合は `GITHUB_TOKEN` を聞かれます (その場で入力しても動きます)
- ウィンドウは**開いたまま**にしてください (閉じる / Ctrl+C でトンネル停止、Gist の URL も自動でクリア)
- `.env` は `.gitignore` 済みなので、トークンがリポジトリに push されることはありません

### コマンドで起動する場合

トークンと Gist 権限が必要です。

### Node.js 版 (推奨)

```powershell
$env:GITHUB_TOKEN="ghp_xxx"
node scripts/update-gist.js
```

### PowerShell 版

```powershell
$env:GITHUB_TOKEN="ghp_xxx"
.\scripts\update-gist.ps1
```

起動すると:

1. `localhost:25565` の待受を確認 (最大 30 秒)
2. `cloudflared tunnel --url http://localhost:25565` を起動
3. ログ中の `https://xxx.trycloudflare.com` を検出し、Gist を更新 (`[OK] Gist更新: ...`)
4. トンネル経由の疎通確認 (`[確認] ... -> HTTP 404 (WebSocket アドレスなので 404 が正常)`)
5. 以降 60 秒ごとに Gist を更新 (ハートビート) — Vercel ページが「最終更新」を表示するため
6. `Ctrl+C` または cloudflared 終了で Gist の `url` をクリア (死んだ URL を残さない)

## 4. Vercel へのデプロイ

`index.html` の先頭にある `GIST_ID` が正しいことを確認し、デプロイします。

```powershell
npx vercel --prod
```

または GitHub リポジトリ (`bismuth47/cloudflared-redirect`) に push して Vercel プロジェクトと自動連携させてください。

> このリポジトリで git を操作する場合は
> `git config --global --add safe.directory D:/server/Eaglercraft-Server-Paper-main/cloudflared`
> が必要です (Windows の所有権エラー回避)。

## 5. プレイヤーの接続方法

Vercel の固定 URL を開くと、**接続アドレス** (例 `https://xxx.trycloudflare.com`) とコピーボタンが表示されます。

1. Eaglercraft クライアント (Web / デスクトップ / Android) を起動
2. **Multiplayer** 画面で **Direct Connect** を選ぶ
3. 表示されたアドレスを貼り付けて接続

> **`https://` は省略しないでください。**
> スキームが無いとクライアントは `ws://` で接続しようとして失敗します。
> ホスト名だけ (例 `xxx.trycloudflare.com`) を使う場合も `wss://` 相当で接続されます。

Vercel のページから自動で転送はしません (アドレスを確認してから手動で遷移する運用を想定)。

## 6. Gist に書かれるデータ

`cloudflared-url.json`:

```json
{
  "url": "https://xxx.trycloudflare.com",
  "host": "xxx.trycloudflare.com",
  "port": 25565,
  "updatedAt": "2026-10-20T13:21:04.000Z",
  "serverName": "My Eaglercraft Server",
  "motd": "&6An EaglercraftX server",
  "protocols": "1.5 / 1.8 / 1.12",
  "online": true
}
```

- `url` / `host` が `null` の間、Vercel ページは「トンネル未接続」と表示
- `updatedAt` が 5 分以上古い場合、ページは「停止している可能性」と警告

Gist を作り直す場合は `gist-initial.json` の中身をそのまま貼り付けてください
(ファイル名は `cloudflared-url.json`、**Public 推奨**)。

## 7. トラブルシューティング

| 症状 | 対処 |
| --- | --- |
| Vercel ページが「トンネル未接続」 | updater が動いていません。`GITHUB_TOKEN` を確認して再起動 |
| Vercel ページが「取得できませんでした」 | GitHub API のレート制限 (未認証取得は 60 回/時/IP)。しばらく待って再取得 |
| ページが古いアドレスを表示 | updater のハートビート (60 秒) が止まっている可能性。PC のスリープ解除後に自動で更新 |
| 接続時にタイムアウト | `cloudflared` が起動しているか、`localhost:25565` に待受があるか確認 |
| `localhost:25565` が待受していない | Minecraft サーバーが起動していません (`run.bat`) |
| 404 が返る | 正常です。WebSocket 用のエンドポイントなので、ブラウザではなくクライアントから接続します |

## 8. 補足

- **Java 版 (Vanilla) プレイヤーはトンネルを使えません。** quick tunnel は HTTP/WS 専用で、
  Minecraft 用の TCP を中継するのは別途 playit.gg などが必要です。
- **固定ドメインが必要なら** cloudflared Named Tunnel (`cloudflared tunnel create/run` + CNAME) を使うと
  Gist 経由の転送が不要になります。その場合もここまでのポート設定 (25565) は同じです。
- `GITHUB_TOKEN` は他人に公開しないでください (PC の環境変数でのみ使用)。
