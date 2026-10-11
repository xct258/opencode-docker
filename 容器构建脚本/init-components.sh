#!/bin/bash
set -e

# 镜像构建期初始化脚本：只做「安装 opencode + 校验」，启动命令在 start.sh 中。
# 安装命令（官方）：curl -fsSL https://opencode.ai/install | bash
# 二进制落到 $HOME/.opencode/bin/opencode（构建期 HOME=/root）。

# 安装必要软件（curl/tar/ca-certificates：官方安装脚本所需；git：opencode 操作仓库所需）
apt update
apt install -y curl ca-certificates tar git jq

# 安装 opencode（构建时可经 OPENCODE_VERSION 锁定版本，例如 0.5.0）
if [ -n "${OPENCODE_VERSION:-}" ]; then
    curl -fsSL https://opencode.ai/install | bash -s -- --version "$OPENCODE_VERSION"
else
    curl -fsSL https://opencode.ai/install | bash
fi

# 软链到 /usr/local/bin，保证任何 PATH 下都能直接用 opencode 命令
ln -sf /root/.opencode/bin/opencode /usr/local/bin/opencode

# 校验安装
opencode --version
