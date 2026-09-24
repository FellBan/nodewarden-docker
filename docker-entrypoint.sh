#!/bin/sh
set -e

mkdir -p /app/data

# JWT_SECRET 稳定化：未显式配置时，从 /app/data 读/写一个持久随机串
# （会话依赖它，重启不能变；落到卷里即可跨重启保持一致）
if [ -z "$JWT_SECRET" ]; then
  SECRET_FILE=/app/data/jwt_secret
  if [ ! -f "$SECRET_FILE" ]; then
    head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 48 > "$SECRET_FILE"
  fi
  JWT_SECRET=$(cat "$SECRET_FILE")
  export JWT_SECRET
fi

echo "FlexVault (NodeWarden 自托管) 启动中 -> 0.0.0.0:${PORT:-3000}"
exec npx tsx --loader src/selfhosted/cloudflare-workers-loader.mjs src/selfhosted/index.ts
