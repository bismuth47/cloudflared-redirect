const { spawn } = require("child_process");

// ===== 設定 (環境変数 or 直書き) =====
const PORT = process.env.PORT || "8080";
const GIST_ID = process.env.GIST_ID || "YOUR_GIST_ID";
const GITHUB_TOKEN = process.env.GITHUB_TOKEN || "YOUR_GITHUB_TOKEN";
const FILE_NAME = "cloudflared-url.json";
// =====================================

if (GIST_ID.startsWith("YOUR_") || GITHUB_TOKEN.startsWith("YOUR_")) {
  console.error("GIST_ID と GITHUB_TOKEN を環境変数で設定してください。");
  console.error('例: $env:GIST_ID="xxx"; $env:GITHUB_TOKEN="ghp_yyy"; node scripts/update-gist.js');
  process.exit(1);
}

const URL_RE = /https:\/\/[a-z0-9-]+\.trycloudflare\.com/i;
let currentUrl = null;

async function updateGist(url) {
  const body = {
    files: {
      [FILE_NAME]: {
        content: JSON.stringify(
          { url, updatedAt: new Date().toISOString(), port: Number(PORT) },
          null,
          2
        ),
      },
    },
  };
  const res = await fetch(`https://api.github.com/gists/${GIST_ID}`, {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${GITHUB_TOKEN}`,
      Accept: "application/vnd.github+json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Gist更新失敗 ${res.status}: ${text}`);
  }
  console.log(`[OK] Gist更新: ${url}`);
}

console.log(`cloudflared tunnel --url http://localhost:${PORT} を起動します...`);
const child = spawn("cloudflared", ["tunnel", "--url", `http://localhost:${PORT}`], {
  stdio: ["ignore", "pipe", "pipe"],
  shell: true,
});

function onLog(chunk) {
  const text = chunk.toString();
  process.stdout.write(text);
  const m = text.match(URL_RE);
  if (m && m[0] !== currentUrl) {
    currentUrl = m[0];
    console.log(`\n[検出] ${currentUrl}`);
    updateGist(currentUrl).catch((e) => console.error("[ERR]", e.message));
  }
}

child.stdout.on("data", onLog);
child.stderr.on("data", onLog);
child.on("exit", (code) => {
  console.log(`cloudflared終了 (code=${code})`);
  process.exit(code ?? 0);
});
