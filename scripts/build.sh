#!/bin/bash

# Umami 构建和启动脚本
# 用法：
#   ./scripts/build.sh          # 仅启动（如果镜像已存在）
#   ./scripts/build.sh --build  # 强制重新构建并启动

set -e

COMPOSE_FILES="-f docker-compose.yml -f docker-compose.build.yml"
COMPOSE_CMD="docker compose $COMPOSE_FILES"

if [ "$1" = "--build" ]; then
    echo "🔨 强制重新构建镜像并启动..."
    $COMPOSE_CMD up --build -d
else
    echo "🚀 启动服务（如果镜像不存在会自动构建）..."
    $COMPOSE_CMD up -d
fi

echo "✅ 服务已启动"
echo "📊 查看状态: docker compose $COMPOSE_FILES ps"
echo "📝 查看日志: docker compose $COMPOSE_FILES logs -f"