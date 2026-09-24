#!/bin/sh
set -e

# JWT_SECRET 稳定化：未显式配置时，从 /data 读/写一个持久随机串（会话依赖它，重启不能变）
if [ -z "$JWT_SECRET" ]; then
  SECRET_FILE="/data/jwt_secret"
  if [ ! -f "$SECRET_FILE" ]; then
    head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 48 > "$SECRET_FILE"
  fi
  JWT_SECRET=$(cat "$SECRET_FILE")
fi

# 写入 Miniflare 本地密钥文件（wrangler dev 读取 .dev.vars）
: > .dev.vars
echo "JWT_SECRET=$JWT_SECRET" >> .dev.vars
if [ -n "$HIDE_WEB_VAULT" ]; then
  echo "HIDE_WEB_VAULT=$HIDE_WEB_VAULT" >> .dev.vars
fi

echo "NodeWarden 启动中 (本地 Miniflare) -> 0.0.0.0:8787"
exec ./node_modules/.bin/wrangler "$@"
