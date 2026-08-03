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

CSV 里的密码仅本地临时用；生产请改 SSH 密钥登录并轮换密码。

GHCR 拉取：公开包可用 `GITHUB_TOKEN`；私有包再加 `GHCR_PULL_TOKEN`。

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
| Package Flutter clients | `ledgerly-web.zip`、`ledgerly-android.apk` → GitHub Release |
| Build & push server image | `ghcr.io/<owner>/ledgerly-server:v0.0.1` + `latest` |
| Publish GitHub Release | 附客户端文件 + release notes |

Web 打包依赖 `apps/client/web/{sqlite3.wasm,drift_worker.js}`（与 `pubspec.lock` 中 drift/sqlite3 版本对齐；可用 `./scripts/fetch_drift_web_assets.sh` 更新）。

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
