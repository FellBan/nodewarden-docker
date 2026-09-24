# syntax=docker/dockerfile:1
# FlexVault (NodeWarden fork) 原生 Node.js 自托管镜像
# 无 Miniflare / 无 Cloudflare 依赖：SQLite 文件 + 本地磁盘存储
# 两阶段：先构建 Web Vault 前端，再拼到运行镜像并挂载 FRONTEND_PATH

# ---------- 阶段 1：构建 Web Vault 前端 ----------
FROM node:22-alpine AS builder
WORKDIR /build
COPY package*.json ./
COPY tsconfig.json ./tsconfig.json
COPY tsconfig.selfhosted.json ./tsconfig.selfhosted.json
RUN npm ci
COPY . .
# webapp 是 Preact/Vite SPA，输出到仓库根 dist/
RUN npm run build

# ---------- 阶段 2：运行镜像 ----------
FROM node:22-alpine
WORKDIR /app

# 仅拷贝清单先装依赖（利用层缓存）
COPY package*.json ./
COPY tsconfig.json ./tsconfig.json
COPY tsconfig.selfhosted.json ./tsconfig.selfhosted.json
RUN npm ci

# 拷贝源码
COPY src ./src
COPY shared ./shared
COPY migrations ./migrations

# 修复 FlexVault 自托管在原生 Node 22 下的 bug：
# ASSETS.fetch 收到 Request 对象时，env.ts 走到 `new URL(input.toString())`，
# 而 Request.toString() === "[object Request]" 导致 ERR_INVALID_URL。
# 改为：Request 实例直接用 input.url。
RUN <<'EOF'
node -e '
const fs=require("fs");
const f="src/selfhosted/env.ts";
let s=fs.readFileSync(f,"utf8");
const old="const url = typeof input === \x27string\x27 ? new URL(input, \x27http://localhost\x27) : new URL(input.toString());";
const neu="const url = input instanceof Request ? new URL(input.url) : typeof input === \x27string\x27 ? new URL(input, \x27http://localhost\x27) : new URL(input.toString());";
if(!s.includes(old)){console.error("PATCH FAILED: target line not found in "+f);process.exit(1);}
s=s.replace(old,neu);
fs.writeFileSync(f,s);
console.log("patched env.ts");
'
EOF

# 拷贝前端构建产物
COPY --from=builder /build/dist ./webapp-dist

RUN mkdir -p /app/data

ENV NODE_ENV=production
ENV DATABASE_PATH=/app/data/nodewarden.db
ENV STORAGE_PATH=/app/data/attachments
ENV PORT=3000
ENV HOST=0.0.0.0
# 让自托管服务把 Web Vault 页面挂到 / 下
ENV FRONTEND_PATH=/app/webapp-dist

EXPOSE 3000

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["npx", "tsx", "--import", "data:text/javascript,import { register } from \"node:module\"; import { pathToFileURL } from \"node:url\"; register(\"./src/selfhosted/cloudflare-workers-loader.mjs\", pathToFileURL(\"./\"));", "src/selfhosted/index.ts"]
