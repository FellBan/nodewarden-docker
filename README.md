# NodeWarden · Docker 部署（CI 推镜像 + Watchtower 自动更新）

把 [shuaiplus/nodewarden](https://github.com/shuaiplus/nodewarden) 打成 Docker 镜像、
自动推到 **Docker Hub**，再在你的 **服务器/VPS** 上用 **Watchtower** 拉镜像实现：
**上游一更新 → CI 重建镜像 → Watchtower 自动拉新镜像重启**。

## 原理
NodeWarden 是 Cloudflare Workers 应用（D1+R2+DurableObjects）。Docker 内用 Miniflare
本地模拟这些绑定（`wrangler dev --local`），数据持久化到卷 `nw-data`。容器可跑在任何
装了 Docker 的机器上，不依赖 Cloudflare 账号。

---

## 第一部分：让镜像自动构建并推到 Docker Hub

需要：一个 GitHub 账号 + 一个 Docker Hub 账号（免费）。

1. 在 GitHub **新建一个仓库**（如 `nodewarden-docker`），把本目录文件推上去：
   `Dockerfile` / `docker-entrypoint.sh` / `.dockerignore` / `.github/workflows/build.yml`。
   （GitHub Actions 每次构建都会 `git clone` 上游最新代码，所以你**不需要** fork 或手动同步上游。）
2. Docker Hub 里创建一个 **Access Token**（Settings → Security → New Access Token，勾选 `Write`）。
3. 在该 GitHub 仓库 **Settings → Secrets and variables → Actions** 添加两个仓库密钥：
   - `DOCKERHUB_USERNAME` = 你的 Docker Hub 用户名
   - `DOCKERHUB_TOKEN` = 上面的 Access Token
4. 开启 Actions（默认开启）。之后：
   - 每次 push 到 `main` 会触发构建；
   - 每 6 小时定时构建一次（抓上游更新）；
   - 也可在 Actions 页面手动 `Run workflow`。
   构建完成后镜像出现在 `docker.io/<你的用户名>/nodewarden:latest`。

---

## 第二部分：在服务器/VPS 部署并自动更新

把本目录的 `docker-compose.yml` 和 `.env.example` 放到服务器某目录，然后：

```bash
cp .env.example .env
# 编辑 .env：填 DOCKERHUB_USERNAME 和 JWT_SECRET（务必改成随机长串）
docker compose up -d
```

- `nodewarden` 容器从 Docker Hub 拉镜像运行，Web Vault 在 `http://<服务器IP>:8787`。
- `watchtower` 每 5 分钟检查一次镜像 digest，CI 一推新 `latest` 它就自动拉取并重启容器。
- **上游更新 → 你无需任何操作**，容器会在几分钟内自更新。

手动触发更新：`docker compose restart nodewarden`（或等 Watchtower 自动）。
查看日志：`docker compose logs -f nodewarden`。

---

## 数据
全部 vault 数据在 Docker 卷 `nw-data`（D1/R2/DO 本地持久化）。删容器不丢数据；
迁移/备份直接备份该卷。

## 注意
- `JWT_SECRET` 务必固定，改了会让已登录会话失效。
- 镜像为**公共**镜像（Docker Hub 免费公共不限量）；若需私有，改 workflow 推送私有仓库并给 Watchtower 配 Docker Hub 登录。
- 想隐藏 Web Vault：`.env` 设 `HIDE_WEB_VAULT=1`。
- 本仓库的 CI 构建需 GitHub 能访问 GitHub.com 与 Docker Hub（云端 Runner 默认可访问）。
