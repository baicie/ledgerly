# 发布与部署 Runbook

目标流程：

1. **客户端打包** → 上传到 **GitHub Release**
2. **服务端镜像** → 推 **GHCR** → SSH 部署到宿主机
3. **PostgreSQL** → **复用服务器已有 PG**（不启 compose 内的 PG）

目标机参考（勿把密码写入仓库）：`82.156.234.84`，用户 `ubuntu`，Docker via SSH。

## 一、一次性准备

### 1. 宿主机 Postgres

在已有 PG 上建库（或本机 `psql` 连过去）：

```bash
export LEDGER_DB_PASSWORD='your-strong-password'
./scripts/provision_host_pg.sh
```

确认 PG 允许 Docker 网桥访问（`pg_hba.conf` / `listen_addresses`）。  
容器内用 `host.docker.internal:5432`（compose 已加 `host-gateway`）。

### 2. 服务器目录

```bash
ssh ubuntu@82.156.234.84
sudo mkdir -p /opt/ledgerly && sudo chown ubuntu:ubuntu /opt/ledgerly
# 从仓库复制示例并改密
scp infrastructure/docker/env.prod.example ubuntu@82.156.234.84:/opt/ledgerly/.env.prod
# 编辑 DATABASE_URL=postgres://ledgerly:...@host.docker.internal:5432/ledgerly
```

### 3. GitHub Secrets（仓库 Settings → Secrets）

| Secret | 用途 |
|--------|------|
| `DEPLOY_HOST` | `82.156.234.84` |
| `DEPLOY_USER` | `ubuntu` |
| `DEPLOY_SSH_KEY` | 私钥全文（**推荐**；不要用 CSV 密码进 CI） |
| `DEPLOY_SSH_PORT` | 可选，默认 22 |
| `ANDROID_KEYSTORE_BASE64` | Android 正式签名 JKS 的 Base64 内容 |
| `ANDROID_KEYSTORE_PASSWORD` | JKS 存储密码 |
| `ANDROID_KEY_ALIAS` | 正式密钥别名，当前为 `ledgerly-release` |
| `ANDROID_KEY_PASSWORD` | JKS 内私钥密码 |

CSV 里的密码仅本地临时用；生产请改 SSH 密钥登录并轮换密码。

GHCR 拉取：公开包可用 `GITHUB_TOKEN`；私有包再加 `GHCR_PULL_TOKEN`。

### 4. Android 正式签名

Android APK 使用固定的长期证书签名。公开证书 SHA-256 指纹同时保存在
[`apps/client/android/release-signing-certificate.sha256`](../../apps/client/android/release-signing-certificate.sha256)：

```text
91:C0:AF:AF:04:68:AC:F8:5C:63:8E:6A:A6:5C:7D:02:2D:9D:24:9A:F8:87:11:CB:B7:46:70:24:BB:D4:B6:0B
```

密钥材料不进入仓库：

- 主副本：`$HOME/Library/Application Support/Ledgerly/Android Signing/ledgerly-release.jks`
- 备份：`$HOME/Documents/Ledgerly Backups/Android Signing/ledgerly-release-2026-08-04.jks`
- 密码：macOS Keychain 中账号 `baicie/ledgerly` 下的 `Ledgerly Android release keystore password` 与 `Ledgerly Android release key password`

目录权限应为 `700`，JKS 权限应为 `600`。轮换 GitHub Secret 前，先用固定指纹验证候选密钥；不要重新生成同名密钥替代丢失的 JKS，否则现有安装无法升级。密钥变更必须作为单独的安全事件处理。

Flutter 与 Android 的官方说明分别见 [Build and release an Android app](https://docs.flutter.dev/deployment/android#sign-the-app) 和 [Sign your app](https://developer.android.com/studio/publish/app-signing)。

## 二、发版（推荐）

在干净的 `main` 上：

```bash
./scripts/release.sh 0.0.1
# 等价于：校验分支干净且与 origin/main 同步 → 打 annotated tag → push
# 预览：./scripts/release.sh 0.0.1 --dry-run
```

手动等价：

```bash
git tag -a v0.0.1 -m "Release v0.0.1"
git push origin v0.0.1
```

触发 [`.github/workflows/release.yml`](../../.github/workflows/release.yml)：

| Job | 产物 |
|-----|------|
| Package Flutter clients | `ledgerly-web.zip`、三个 ABI 拆分 APK → GitHub Release |
| Build & push server image | `ghcr.io/<owner>/ledgerly-server:v0.0.1` + `latest` |
| Publish GitHub Release | 附客户端文件 + release notes |

Web 打包依赖 `apps/client/web/{sqlite3.wasm,drift_worker.js}`（与 `pubspec.lock` 中 drift/sqlite3 版本对齐；可用 `./scripts/fetch_drift_web_assets.sh` 更新）。

Android APK 按 ABI 拆分发布：大多数现代手机使用 `ledgerly-android-arm64-v8a.apk`，旧版 32 位 ARM 设备使用 `ledgerly-android-armeabi-v7a.apk`，x86_64 设备或模拟器使用 `ledgerly-android-x86_64.apk`。

Release workflow 会在上传前调用 `apksigner verify --print-certs`，并要求三个 APK 都只有一个签名证书且匹配上述固定指纹。缺少 Secret、密码或别名错误、JKS 被替换、APK 签名无效时，发布都会失败。

正式签名启用前发布的 APK 使用 Android debug 证书，不能直接覆盖升级到正式签名版本；用户需要先卸载旧 APK，再安装首个正式签名版本。此后所有版本必须继续使用同一 JKS。

手动部署：

- Actions → **Release** → **Run workflow** →勾选 `deploy`
- 或本机：

```bash
export DEPLOY_HOST=82.156.234.84 DEPLOY_USER=ubuntu
export DEPLOY_SSH_KEY_FILE=~/.ssh/id_ed25519
export LEDGER_IMAGE=ghcr.io/baicie/ledgerly-server:latest
./scripts/deploy_remote.sh
```

## 三、本地只构建镜像

```bash
docker build -f server/Dockerfile -t ledgerly-server:local .
docker compose -f infrastructure/docker/docker-compose.prod.yml --env-file .env.prod up -d
```

开发用内置 PG 仍可用：`infrastructure/docker/docker-compose.yml`（仅本地）。

## 四、验收

```bash
curl -sf http://82.156.234.84:8080/health/ready
# 客户端：Release 页下载 web/apk；API 指向服务器 OBJECT_STORE_PUBLIC_BASE / API 地址
```

## 五、回滚

```bash
# 在服务器
cd /opt/ledgerly
LEDGER_IMAGE=ghcr.io/baicie/ledgerly-server:v0.0.9 \
  docker compose -f docker-compose.prod.yml --env-file .env.prod up -d
```
