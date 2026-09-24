# syntax=docker/dockerfile:1

# ---------- Build stage ----------
FROM node:22-bookworm-slim AS build
WORKDIR /app

# 原生模块（sharp/esbuild 等）在个别平台需要构建工具；装上以防万一
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 make g++ git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 只拷贝清单先装依赖，利用层缓存
COPY package*.json ./
RUN npm install

# 拷贝源码并构建 Web Vault 静态资源（wrangler.toml 的 [assets].directory = ./dist）
COPY . .
RUN npm run build

# ---------- Runtime stage ----------
FROM node:22-bookworm-slim AS runtime
WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# 把构建产物 + 依赖一起带过来（wrangler 是 devDependency，运行时需要）
COPY --from=build /app /app

EXPOSE 8787
VOLUME ["/data"]

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
# 本地模式运行（Miniflare 模拟 Cloudflare Workers：D1/R2/DurableObjects），数据持久化到 /data
CMD ["wrangler", "dev", "-c", "wrangler.toml", "--local", "--ip", "0.0.0.0", "--port", "8787", "--persist-to", "/data"]
