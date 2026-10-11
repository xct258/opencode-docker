#!/bin/bash

# 持久化目录（对应 compose 中的挂载卷；config/data 缺省由 opencode 自行生成）
mkdir -p /app/workspace /root/.config/opencode /root/.local/share/opencode

# opencode web 默认随机端口，容器内固定为 $PORT（默认 4096），便于映射与反代
PORT="${PORT:-4096}"

# 经网络访问时官方要求设置鉴权；未设置则无密码，仅限内网使用
if [ -z "${OPENCODE_SERVER_PASSWORD:-}" ]; then
    echo "警告：未设置 OPENCODE_SERVER_PASSWORD，web 界面无鉴权，仅限内网使用" >&2
fi

# 在工作目录启动，web 会话默认落到该目录
cd /app/workspace

# 前台启动（它是容器主进程，退出即容器停止）
exec opencode web --hostname 0.0.0.0 --port "$PORT"
