"use strict";
/**
 * Eaglercraft サーバー公開用 updater
 *
 *  1. EaglercraftXServer (Paper プラグイン) の待受ポート (既定 25565) を待受確認
 *  2. `cloudflared tunnel --url http://localhost:25565` を起動
 *  3. ログからランダム URL (https://xxx.trycloudflare.com) を検出
 *  4. GitHub Gist へ最新 URL を書き込み (Vercel の固定ページが 이를参照する)
 *
 * 設定の優先順位: 環境変数 > server.config.json > 既定値
 */

const { spawn } = require("child_process");
const fs = require("fs");
const net = require("net");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const CONFIG_FILE = path.join(ROOT, "server.config.json");

const DEFAULT_GIST_ID = "ace74a8eec7a4f2ad49aa11c7e222412";
const FILE_NAME = "cloudflared-url.json";
const URL_RE = /https:\/\/[a-z0-9-]+(?:\.[a-z0-9-]+)*\.trycloudflare\.com/i;

const DEFAULTS = {
  port: 25565,
  cloudflared: "cloudflared",
  heartbeatMs: 300000,
  readyTimeoutMs: 30000,
  serverName: "Eaglercraft Server",
  motd: "",
  protocols: "1.5 / 1.8 / 1.12",
};

// ===== 設定読み込み =====
function loadConfig() {
  let fileCfg = {};
  if (fs.existsSync(CONFIG_FILE)) {
    try {
      fileCfg = JSON.parse(fs.readFileSync(CONFIG_FILE, "utf8"));
    } catch (e) {
      console.error(`[WARN] ${CONFIG_FILE} を読み込めませんでした: ${e.message}`);
    }
  }
  const num = (v, d) =>
    v === undefined || v === null || v === "" || isNaN(Number(v)) ? d : Number(v);
  return {
    port: num(process.env.PORT ?? fileCfg.port, DEFAULTS.port),
    gistId: process.env.GIST_ID || fileCfg.gistId || DEFAULT_GIST_ID,
    token: process.env.GITHUB_TOKEN || "",
    cloudflared: process.env.CLOUDFLARED_PATH || fileCfg.cloudflared || DEFAULTS.cloudflared,
    heartbeatMs: num(process.env.HEARTBEAT_MS, DEFAULTS.heartbeatMs),
    readyTimeoutMs: num(process.env.READY_TIMEOUT_MS, DEFAULTS.readyTimeoutMs),
    serverName: process.env.SERVER_NAME || fileCfg.serverName || DEFAULTS.serverName,
    motd: process.env.MOTD ?? fileCfg.motd ?? DEFAULTS.motd,
    protocols: process.env.PROTOCOLS || fileCfg.protocols || DEFAULTS.protocols,
  };
}

const cfg = loadConfig();

if (!cfg.token) {
  console.error("GITHUB_TOKEN が設定されていません。");
  console.error('例: $env:GITHUB_TOKEN="ghp_xxx"; node scripts/update-gist.js');
  process.exit(1);
}
if (cfg.gistId.startsWith("YOUR_")) {
  console.error("GIST_ID が設定されていません。");
  process.exit(1);
}

// ===== 状態 =====
let currentUrl = null;
let updating = false;

function buildState() {
  let host = null;
  if (currentUrl) {
    try {
      host = new URL(currentUrl).host;
    } catch (_) {
      host = null;
    }
  }
  return {
    url: currentUrl,
    host,
    port: cfg.port,
    updatedAt: new Date().toISOString(),
    serverName: cfg.serverName,
    motd: cfg.motd,
    protocols: cfg.protocols,
    online: !!currentUrl,
  };
}

async function writeGist() {
  if (updating) return;
  updating = true;
  try {
    const body = { files: { [FILE_NAME]: { content: JSON.stringify(buildState(), null, 2) } } };
    const res = await fetch(`https://api.github.com/gists/${cfg.gistId}`, {
      method: "PATCH",
      headers: {
        Authorization: `Bearer ${cfg.token}`,
        Accept: "application/vnd.github+json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`Gist更新失敗 ${res.status}: ${text.slice(0, 300)}`);
    }
    console.log(`[OK] Gist更新: ${currentUrl ?? "(url をクリア)"}`);
  } catch (e) {
    console.error("[ERR]", e.message);
  } finally {
    updating = false;
  }
}

// ===== 待受確認 =====
function waitForPort(port, timeoutMs) {
  return new Promise((resolve) => {
    const start = Date.now();
    let done = false;
    const finish = (ok) => {
      if (done) return;
      done = true;
      resolve(ok);
    };
    const attempt = () => {
      const sock = net.connect({ host: "127.0.0.1", port });
      const fail = () => {
        sock.destroy();
        if (Date.now() - start >= timeoutMs) {
          console.error(`[ERR] localhost:${port} が ${Math.round(timeoutMs / 1000)}秒待っても待ち受けしません。`);
          finish(false);
          return;
        }
        setTimeout(attempt, 1000);
      };
      sock.setTimeout(2000, fail);
      sock.once("connect", () => {
        sock.destroy();
        finish(true);
      });
      sock.once("error", fail);
    };
    attempt();
  });
}

// ===== トンネル経由の疎通確認 =====
// トンネル発行直後は到達できるまで数秒かかることがあるため数回リトライする
async function verifyTunnel(url, attempts = 8, intervalMs = 4000) {
  for (let i = 1; i <= attempts; i++) {
    try {
      const res = await fetch(url, { redirect: "manual" });
      console.log(
        `[確認] ${url} -> HTTP ${res.status}` +
          (res.status === 404 ? " (WebSocket アドレスなので 404 が正常)" : "")
      );
      return;
    } catch (e) {
      if (i === attempts) {
        console.error(`[WARN] 疎通確認に失敗しました (${attempts}回): ${e.message}`);
        return;
      }
      console.log(`[確認] まだ到達できません (${i}/${attempts})...`);
      await new Promise((r) => setTimeout(r, intervalMs));
    }
  }
}

// ===== トンネル起動 =====
console.log(`cloudflared tunnel --url http://localhost:${cfg.port} を起動します...`);

// shell:true + 単一コマンド文字列 (引数配列で渡す と Node の非推奨警告が出る)
const tunnelCmd = `"${cfg.cloudflared}" tunnel --url http://localhost:${cfg.port} --no-autoupdate`;
const child = spawn(tunnelCmd, { stdio: ["ignore", "pipe", "pipe"], shell: true });

let heartbeat = null;

function onLog(chunk) {
  const text = chunk.toString();
  process.stdout.write(text);
  const m = text.match(URL_RE);
  if (m && m[0] !== currentUrl) {
    currentUrl = m[0];
    console.log(`\n[検出] ${currentUrl}`);
    writeGist();
    // トンネル経由の疎通確認 (404 = Eaglercraft の WebSocket 案内ページなので正常)
    verifyTunnel(currentUrl);
    if (!heartbeat) {
      heartbeat = setInterval(() => {
        if (currentUrl) writeGist();
      }, cfg.heartbeatMs);
    }
  }
}

child.stdout.on("data", onLog);
child.stderr.on("data", onLog);

child.on("error", (e) => {
  console.error("[ERR] cloudflared を起動できません:", e.message);
  process.exit(1);
});

child.on("exit", async (code) => {
  if (heartbeat) clearInterval(heartbeat);
  currentUrl = null;
  await writeGist(); // 死んだ URL を残さない
  console.log(`cloudflared終了 (code=${code})`);
  process.exit(code ?? 0);
});

// shell:true で起動しているため、終了時はプロセスツリーごと止める
function killTunnel() {
  if (!child || child.exitCode !== null) return;
  if (process.platform === "win32") {
    spawn("taskkill", ["/pid", String(child.pid), "/T", "/F"], { stdio: "ignore" });
  } else {
    child.kill("SIGTERM");
  }
}

process.on("SIGINT", async () => {
  console.log("\n中断しました。Gist をクリアします...");
  if (heartbeat) clearInterval(heartbeat);
  killTunnel();
  currentUrl = null;
  await writeGist();
  process.exit(0);
});

// 起動前にサーバーが alive かをチェック
waitForPort(cfg.port, cfg.readyTimeoutMs).then((ok) => {
  if (!ok) process.exit(1);
  console.log(`[OK] localhost:${cfg.port} の待受を確認しました`);
});
