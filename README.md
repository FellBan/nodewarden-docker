# NodeWarden · Docker 部署（基于 FlexVault 原生 Node.js 模式 + Watchtower 自动更新）

基于 [FlexVault](https://github.com/lj5645/FlexVault)（NodeWarden 的 fork，自带原生 Node.js 自托管模式）
构建 Docker 镜像、自动推到 **GHCR（GitHub Packages）**，再在服务器上用 **Watchtower** 拉镜像：
**上游一更新 → 镜像自动重建 → 容器自动拉新重启，全程零操作**。

> 镜像地址：`ghcr.io/fellban/nodewarden:latest`

## 为什么这么简单

FlexVault 把 NodeWarden 原本的 Cloudflare Workers 运行时（D1/R2/DurableObjects）重写成普通
Node.js 进程：**SQLite 本地文件 + 本地磁盘附件 + WebSocket 通知**。所以容器里就是个标准
Node 服务，不需要 Miniflare、不需要 wrangler、不需要 Cloudflare 账号。整套部署就是一条
`docker run` / 一份 `docker-compose.yml`。

---

## Quick Start (Docker)

在任意装了 Docker 的服务器上，三步跑起来：

```bash
# 1. 下载 compose 与 env 模板
curl -fsSL https://raw.githubusercontent.com/FellBan/nodewarden-docker/main/docker-compose.yml -o docker-compose.yml
curl -fsSL https://raw.githubusercontent.com/FellBan/nodewarden-docker/main/.env.example -o .env

# 2. 生成 JWT 密钥并写入 .env（留空也能跑：容器会自动生成并持久化）
JWT=$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 48)
sed -i "s#^JWT_SECRET=.*#JWT_SECRET=$JWT#" .env

# 3. 启动
docker compose up -d
```

完成后访问 **Web Vault：`http://<服务器IP>:3000`**。
`watchtower` 每 5 分钟检测镜像 digest，CI 一推新 `latest` 即自动拉取重启，你无需任何操作。

查看日志：`docker compose logs -f nodewarden`

极简单容器（不用 compose）：

```bash
docker run -d \
  --name nodewarden \
  -p 3000:3000 \
  -e JWT_SECRET=$(openssl rand -hex 32) \
  -v nodewarden-data:/app/data \
  --restart unless-stopped \
  ghcr.io/fellban/nodewarden:latest
```

---

## Docker Compose

```yaml
services:
  nodewarden:
    image: ghcr.io/fellban/nodewarden:latest
    container_name: nodewarden
    restart: unless-stopped
    ports:
      - "${NW_PORT:-3000}:3000"
    environment:
      JWT_SECRET: ${JWT_SECRET}
      HIDE_WEB_VAULT: ${HIDE_WEB_VAULT:-}
      TZ: ${TZ:-Asia/Shanghai}
    volumes:
      - nw-data:/app/data
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
    healthcheck:
      test: ["CMD", "node", "-e", "require('net').connect(3000,'127.0.0.1',()=>process.exit(0)).on('error',()=>process.exit(1))"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 60s

  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --interval 300 --label-enable --cleanup
    environment:
      WATCHTOWER_MONITOR_ONLY: "false"
      WATCHTOWER_NOTIFICATIONS: ${WATCHTOWER_NOTIFICATIONS:-}

volumes:
  nw-data:
```

### 环境变量

| 变量 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `JWT_SECRET` | 否* | 自动生成 | JWT 签名密钥，至少 32 位；留空则容器在 `/app/data/jwt_secret` 自动生成并持久化 |
| `NW_PORT` | 否 | `3000` | 宿主机映射端口 |
| `TZ` | 否 | `Asia/Shanghai` | 时区 |
| `HIDE_WEB_VAULT` | 否 | 空 | 设为 `1` 隐藏 Web Vault，仅保留 API |
| `WATCHTOWER_NOTIFICATIONS` | 否 | 空 | Watchtower 通知方式（gotify / shoutrrr 格式） |

\* 强烈建议显式固定 `JWT_SECRET`，否则容器重建若卷丢失会让已登录会话失效。

### 启动 / 停止 / 更新

```bash
docker compose up -d                              # 启动
docker compose down                              # 停止（不删数据卷）
docker compose pull && docker compose up -d      # 手动拉最新镜像重启
docker compose logs -f nodewarden                # 看日志
```

---

## 原理

FlexVault 是 NodeWarden 的 fork，增加了原生 Node.js 自托管运行时：
- **数据库**：SQLite 文件（`@libsql/client`），位于 `/app/data/nodewarden.db`，无需外部数据库
- **附件**：本地磁盘 `/app/data/attachments`（R2 兼容适配器）
- **实时通知**：WebSocket（替代 Durable Object）
- 容器可跑在任何装了 Docker 的机器上，不依赖 Cloudflare

## CI：仅上游有变化才构建

`.github/workflows/build.yml` 逻辑：
1. 每小时（也可手动 Run workflow）取 FlexVault 上游最新 commit；
2. 与本仓库 `last-built.sha` 比对，**相同则直接跳过**，不构建；
3. 有变化才：克隆上游 → 用本仓库 `Dockerfile` 构建镜像 → 推
   `ghcr.io/fellban/nodewarden:latest`（同时打 `sha-xxxxxxx` 版本标签）→
   把 `last-built.sha` 提交回本仓库。

镜像在本仓库 **Packages** 页可见。**不需要 Docker Hub，不需要配任何 Secrets**
（推镜像用内置 `GITHUB_TOKEN`）。

> **首次构建后需把镜像设为公开（一次性）**：
> 仓库 → Packages → `nodewarden` → Package settings → Danger Zone →
> Change visibility → **Public**。否则服务器上 Watchtower 拉不到镜像。

## 数据

全部 vault 数据在 Docker 卷 `nw-data`（挂载到容器 `/app/data`）：含 `nodewarden.db`
数据库与 `attachments/` 附件目录。删容器不丢数据；备份直接备份该卷
（`docker volume inspect nodewarden-docker_nw-data` 看路径）。

## 注意

- 建议显式固定 `JWT_SECRET`，改了会让已登录会话失效。
- 镜像默认推送为 **私有**，首次构建后按上面说明改为 Public。
- 想隐藏 Web Vault：`.env` 设 `HIDE_WEB_VAULT=1`。
- 手动触发重建：本仓库 Actions → Run workflow → 勾选 `force`。
