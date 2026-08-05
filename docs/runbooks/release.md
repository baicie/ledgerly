# 发布与部署 Runbook

目标流程：

1. **客户端打包** → 上传到 **GitHub Release**
2. **服务端镜像** → 推 **GHCR** → GitHub Actions 自动部署到宿主机
3. **PostgreSQL** → 默认使用 VM 专用容器；有现成 PG 时可改用基础 compose

目标机参考（勿把密码写入仓库）：`82.156.234.84`，用户 `ubuntu`，Docker via SSH。

## 一、一次性准备

### 1. PostgreSQL

目标机没有可从 Docker 网桥访问的宿主 PostgreSQL 时，使用仓库提供的 VM
override，它会创建私有的 `ledgerly-postgres` 容器和独立卷：

```bash
cp infrastructure/docker/env.vm.example /opt/ledgerly/.env.prod
# 修改 POSTGRES_PASSWORD、DATABASE_URL、JWT_*、OBJECT_STORE_HMAC_SECRET、
# CORS_ALLOWED_ORIGINS 和 OBJECT_STORE_PUBLIC_BASE
```

如果复用已有 PG，则执行 `scripts/provision_host_pg.sh` 建库，并将
`DATABASE_URL` 改成 `host.docker.internal:5432`；此时只使用
`docker-compose.prod.yml`，不要同时启用 VM override。

### 2. 服务器目录

```bash
ssh ubuntu@82.156.234.84
sudo mkdir -p /opt/ledgerly && sudo chown ubuntu:ubuntu /opt/ledgerly
# VM 模式复制示例并改密
scp infrastructure/docker/env.vm.example ubuntu@82.156.234.84:/opt/ledgerly/.env.prod
# 编辑 POSTGRES_PASSWORD、DATABASE_URL=postgres://ledgerly:...@postgres:5432/ledgerly
# 设置 CORS_ALLOWED_ORIGINS=https://实际的-Web-站点域名
# AUTH_COOKIE_SECURE 必须保持 true，并在 TLS 反向代理后对外服务
```

### 3. GitHub Secrets（仓库 Settings → Secrets）

| Secret | 用途 |
|--------|------|
| `DEPLOY_HOST` | `82.156.234.84` |
| `DEPLOY_USER` | `ubuntu` |
| `DEPLOY_SSH_KEY` | 私钥全文（**推荐**；不要用 CSV 密码进 CI） |
| `DEPLOY_SSH_PORT` | 可选，默认 22 |
| `DEPLOY_HOST_FINGERPRINT` | SSH 主机指纹（`SHA256:...`） |
| `ANDROID_KEYSTORE_BASE64` | Android 正式签名 JKS 的 Base64 内容 |
| `ANDROID_KEYSTORE_PASSWORD` | JKS 存储密码 |
| `ANDROID_KEY_ALIAS` | 正式密钥别名，当前为 `ledgerly-release` |
| `ANDROID_KEY_PASSWORD` | JKS 内私钥密码 |

CSV 里的密码仅本地临时用；生产请改 SSH 密钥登录并轮换密码。

GHCR 拉取：公开包可用 `GITHUB_TOKEN`；私有包再加 `GHCR_PULL_TOKEN`。

仓库变量 `LEDGERLY_API_BASE_URL` 是可选的客户端初始值。默认要求它是生产
API 的 HTTPS origin，不能包含路径、查询或凭据。若原生客户端必须连接没有
TLS 的服务，可将布尔仓库变量 `LEDGERLY_API_REQUIRE_HTTPS` 设为 `false`，
以允许公网 HTTP；默认值为 `true`（原生私有网段 HTTP 仍可用），回环地址仍会
被 Release 拒绝。Web
Release 仍强制 HTTPS，因为 Web 刷新会话使用 `Secure`、`HttpOnly` Cookie。
已保存的用户配置优先于这些变量；用户保存的空值会覆盖初始地址并选择纯
本地模式。变量为空时 Release 仍会正常打包，客户端首次启动直接进入本地
账本，不发起认证或同步请求。

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
./scripts/release.sh 0.0.4
# 等价于：校验分支干净且与 origin/main 同步 → 打 annotated tag → push
# 预览：./scripts/release.sh 0.0.4 --dry-run
```

手动等价：

```bash
git tag -a v0.0.4 -m "Release v0.0.4"
git push origin v0.0.4
```

触发 [`.github/workflows/release.yml`](../../.github/workflows/release.yml)：

| Job | 产物 |
|-----|------|
| Package Flutter clients | `ledgerly-web.zip`、三个 ABI 拆分 APK → GitHub Release |
| Build & push server image | `ghcr.io/<owner>/ledgerly-server:v0.0.4` + `0.0.4` + `latest` |
| Publish GitHub Release | 附客户端文件 + release notes |

Web 打包依赖 `apps/client/web/{sqlite3.wasm,drift_worker.js}`（与 `pubspec.lock` 中 drift/sqlite3 版本对齐；可用 `./scripts/fetch_drift_web_assets.sh` 更新）。
Web 和正式客户端可在没有预置地址时构建：

```bash
flutter build web --release
```

需要预置初始地址时，可额外传入
`--dart-define=LEDGERLY_API_BASE_URL="$PRODUCTION_API_ORIGIN"`。若原生 Release
需要 HTTP，再传入
`--dart-define=LEDGERLY_API_REQUIRE_HTTPS=false`；Web 构建仍不能使用 HTTP
会话。API 地址选填；留空时客户端仅使用 Drift 本地数据库，不恢复远端会话或
同步。登录页、启动恢复页和设置页均可保存或清空地址；Release 默认仅接受
非本机 HTTPS origin，Native 在关闭 HTTPS 要求后也可使用公网 HTTP，Web
Release 还要求使用默认 HTTPS 端口（443），Native 可使用自定义 HTTPS 端口。

服务端 `CORS_ALLOWED_ORIGINS` 填 Web 应用的 origin（协议、域名和端口），
不要填 API 地址或路径。Web Refresh Token 仅通过 `Secure`、`HttpOnly`
Cookie 传输，因此 API 和 Web 站点都必须使用 TLS。Cookie 使用
`SameSite=Strict`，跨 origin 部署时 Web 与 API 仍须属于同一站点（例如
`app.ledgerly.example.com` 与 `api.ledgerly.example.com`）；不同注册域名的
组合不会发送刷新 Cookie。

Android APK 按 ABI 拆分发布：大多数现代手机使用 `ledgerly-android-arm64-v8a.apk`，旧版 32 位 ARM 设备使用 `ledgerly-android-armeabi-v7a.apk`，x86_64 设备或模拟器使用 `ledgerly-android-x86_64.apk`。

Release workflow 会在上传前调用 `apksigner verify --print-certs`，并要求三个 APK 都只有一个签名证书且匹配上述固定指纹。缺少 Secret、密码或别名错误、JKS 被替换、APK 签名无效时，发布都会失败。

正式签名启用前发布的 APK 使用 Android debug 证书，不能直接覆盖升级到正式签名版本；用户需要先卸载旧 APK，再安装首个正式签名版本。此后所有版本必须继续使用同一 JKS。

服务端自动部署：

- 合并到 `main` 且变更命中 `server/**`、`infrastructure/docker/**` 或部署 workflow
  后，`.github/workflows/deploy-server.yml` 会自动运行验证、构建、镜像 smoke test、
  文件同步和远端健康检查。
- Actions → **Deploy Ledgerly Server** → **Run workflow** 可手动部署当前 ref。
- 手动填写 `image_tag`（例如 `v0.0.5` 或 `sha-...`）会跳过构建并部署该 GHCR
  镜像，用于回滚。

首次启用前，在目标机执行一次目录初始化并生成 `.env.prod`；然后把 SSH 公钥加入
`ubuntu` 的 `authorized_keys`，将私钥和指纹写入上表 Secrets。workflow 会将服务绑定
到 `127.0.0.1:8081`，外部访问应通过 TLS 反向代理。

本机手工部署仅用于故障排查：

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
# 目标机默认只监听回环地址，先通过 SSH 登录后验收
ssh ubuntu@82.156.234.84 'curl -sf http://127.0.0.1:8081/health/ready'
# 客户端：Release 页下载 web/apk；验证空地址本地模式及可选 HTTPS/原生 HTTP API 模式
```

## 五、回滚

在 Actions 手动运行 **Deploy Ledgerly Server**，将 `image_tag` 填入上一个已验证的
GHCR tag。远端 workflow 在新版本健康检查失败时也会自动恢复容器之前使用的镜像。
