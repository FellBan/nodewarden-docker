# syntax=docker/dockerfile:1
# FlexVault (NodeWarden fork) 原生 Node.js 自托管镜像
# 无 Miniflare / 无 Cloudflare 依赖：SQLite 文件 + 本地磁盘存储
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

RUN mkdir -p /app/data

ENV NODE_ENV=production
ENV DATABASE_PATH=/app/data/nodewarden.db
ENV STORAGE_PATH=/app/data/attachments
ENV PORT=3000
ENV HOST=0.0.0.0

EXPOSE 3000

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["npx", "tsx", "--loader", "src/selfhosted/cloudflare-workers-loader.mjs", "src/selfhosted/index.ts"]
