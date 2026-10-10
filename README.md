# cloudflared ランダムURL → Vercel リダイレクトサイト

`cloudflared tunnel --url http://localhost:8080` で発行されるランダムな
`https://xxx.trycloudflare.com` が再起動のたびに変わる問題を、
Vercelの固定URLにアクセスすれば最新URLへ自動転送される仕組みで解決します。

構成: DB不要。`GitHub Gist` を「最新URLの置き場所」にする。

```
[自宅PC] cloudflared起動 → URL検出 → GistをPATCH更新
[Vercel] index.html → Gistを取得 → 最新URLへ location.href で転送
```

## 1. Gistを作る (1回だけ)

1. https://gist.github.com にアクセス
2. ファイル名 `cloudflared-url.json`、内容は `gist-initial.json` と同じ:
   ```json
   {"url":null,"updatedAt":null,"port":8080}
   ```
3. **Create public gist** (Public推奨。Secretでも可)
4. URL末尾のIDを控える → これが `GIST_ID`
   例: `https://gist.github.com/you/a1b2c3...` → `a1b2c3...`

## 2. GitHubトークンを作る (1回だけ)

1. https://github.com/settings/tokens/new
2. 権限は `gist` のみにチェック → Generate
3. `ghp_xxx...` を控える → これが `GITHUB_TOKEN`
   ※ PC側だけで使い、Vercelには設定しない

## 3. Vercel側の設定

`index.html` の先頭にある1行だけ書き換え:

```js
const GIST_ID = "YOUR_GIST_ID"; // ← ここを手順1のIDに
```

その後このフォルダをVercelにデプロイ:

```powershell
npx vercel --prod
```

または GitHubリポジトリにpushしてVercelと連携。

## 4. PC側で起動する (cloudflared更新のたび)

### Node.js版 (推奨):

```powershell
$env:GIST_ID="手順1のID"
$env:GITHUB_TOKEN="ghp_xxx"
$env:PORT="8080"
node scripts/update-gist.js
```

### PowerShell版:

```powershell
$env:GIST_ID="手順1のID"
$env:GITHUB_TOKEN="ghp_xxx"
.\scripts\update-gist.ps1 -Port 8080
```

起動すると `cloudflared` が立ち上がり、ログ中の
`https://xxx.trycloudflare.com` を検出して自動でGistを更新します。
cloudflaredを再起動してURLが変わっても、数秒でGistが書き換わります。

## 動作確認

1. PCで updater を起動し `[OK] Gist更新: https://...` が出ることを確認
2. VercelのURLにアクセス → 自動で trycloudflare のURLに飛べば成功
3. cloudflaredを Ctrl+C → 再起動 → 新URLに変わってもVercel側は再デプロイ不要

## 注意

- `GITHUB_TOKEN` は他人に公開しない (PCの環境変数でのみ使用)
- Gist APIの未認証取得制限は 60回/時/IP。訪問ごとに1回取得するだけなので通常は問題なし
- より本格運用 (Basic認証・サーバー側302・アクセス制御) が必要になったら Vercel KV 版への移行を検討
- 根本解決として、固定ドメインが使える cloudflared Named Tunnel (`cloudflared tunnel create/run + CNAME`) も検討候補
