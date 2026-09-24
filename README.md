# NodeWarden · Docker 部署（GHCR 镜像 + Watchtower 自动更新）

把 [shuaiplus/nodewarden](https://github.com/shuaiplus/nodewarden) 打成 Docker 镜像、自动推到
**GHCR（GitHub Packages）**，再在服务器上用 **Watchtower** 拉镜像：
**上游一更新 → 镜像自动重建 → 容器自动拉新重启，全程零操作**。

> 镜像地址：`ghcr.io/fellban/nodewarden:latest`

---

## Quick Start (Docker)

在任意装了 Docker 的服务器上，三步跑起来：

```bash
# 1. 下载 compose 与 env 模板
curl -fsSL https://raw.githubusercontent.com/FellBan/nodewarden-docker/main/docker-compose.yml -o docker-compose.yml
curl -fsSL https://raw.githubusercontent.com/FellBan/nodewarden-docker/main/.env.example -o .env

# 2. 生成 JWT 密钥并写入 .env（至少 32 位随机串）
JWT=$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 48)
sed -i "s#^JWT_SECRET=.*#JWT_SECRET=$JWT#" .env

# 3. 启动
docker compose up -d
```

完成后访问 **Web Vault：`http://<服务器IP>:8787`**。
`watchtower` 每 5 分钟检测镜像 digest，CI 一推新 `latest` 即自动拉取重启，你无需任何操作。

查看日志：`docker compose logs -f nodewarden`

---

## Docker Compose

部署核心是 `docker-compose.yml`，它拉起两个服务：`nodewarden`（服务端）与 `watchtower`（自动更新器）。

### compose 文件

```yaml
services:
  nodewarden:
    image: ghcr.io/fellban/nodewarden:latest
    container_name: nodewarden
    restart: unless-stopped
    ports:
      - "${NW_PORT:-8787}:8787"
    environment:
      JWT_SECRET: ${JWT_SECRET}
      HIDE_WEB_VAULT: ${HIDE_WEB_VAULT:-}
      TZ: ${TZ:-Asia/Shanghai}
    volumes:
      - nw-data:/data
    labels:
      # 只允许 Watchtower 更新带此标签的容器
      - "com.centurylinklabs.watchtower.enable=true"
    healthcheck:
      test: ["CMD", "node", "-e", "require('net').connect(8787,'127.0.0.1',()=>process.exit(0)).on('error',()=>process.exit(1))"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 90s

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

### 字段说明

| 项 | 含义 |
|---|---|
| `image` | GHCR 上的 `nodewarden:latest`，由 CI 自动推送 |
| `ports` | 宿主机 `${NW_PORT:-8787}` → 容器 `8787`（Web Vault / API 端口） |
| `JWT_SECRET` | 必填，JWT 签名密钥，**务必固定且保密**，改了会让已登录会话失效 |
| `HIDE_WEB_VAULT` | 可选，设为 `1` 隐藏 Web Vault，仅保留 API 给 Bitwarden 客户端 |
| `TZ` | 时区，默认 `Asia/Shanghai` |
| `nw-data` 卷 | 持久化全部 vault 数据（D1/R2/DO 本地存储），删容器不丢数据 |
| `watchtower` | 挂载 docker.sock，每 300 秒检查镜像 digest，`--label-enable` 只更新带 `watchtower.enable=true` 标签的容器，`--cleanup` 清理旧镜像 |

### 启动 / 停止 / 更新

```bash
docker compose up -d          # 启动
docker compose down           # 停止（不删数据卷）
docker compose pull && docker compose up -d   # 手动拉最新镜像重启
docker compose logs -f nodewarden             # 看日志
```

---

## 原理

NodeWarden 是 Cloudflare Workers 应用（D1+R2+DurableObjects）。Docker 内用 Miniflare
本地模拟这些绑定（`wrangler dev --local`），数据持久化到卷 `nw-data`。容器可跑在
任何装了 Docker 的机器上，不依赖 Cloudflare 账号。

## CI：仅上游有变化才构建

`.github/workflows/build.yml` 逻辑：
1. 每小时（也可手动 Run workflow）取上游最新 commit；
2. 与本仓库 `last-built.sha` 比对，**相同则直接跳过**，不构建；
3. 有变化才：克隆上游 → 注入 Dockerfile → 构建镜像 → 推
   `ghcr.io/fellban/nodewarden:latest`（同时打 `sha-xxxxxxx` 版本标签）→
   把 `last-built.sha` 提交回本仓库。

镜像在本仓库 **Packages** 页可见。**不需要 Docker Hub，不需要配任何 Secrets**
（推镜像用内置 `GITHUB_TOKEN`）。

> **首次构建后需把镜像设为公开（一次性）**：
> 仓库 → Packages → `nodewarden` → Package settings → Danger Zone →
> Change visibility → **Public**。否则服务器上 Watchtower 拉不到镜像。

## 数据

全部 vault 数据在 Docker 卷 `nw-data`（D1/R2/DO 本地持久化）。删容器不丢数据；
迁移/备份直接备份该卷（`docker volume inspect nodewarden-docker_nw-data` 看路径）。

## 注意

- `JWT_SECRET` 务必固定，改了会让已登录会话失效。
- 镜像默认推送为 **私有**，首次构建后按上面说明改为 Public。
- 想隐藏 Web Vault：`.env` 设 `HIDE_WEB_VAULT=1`。
- 手动触发重建：本仓库 Actions → Run workflow → 勾选 `force`。
