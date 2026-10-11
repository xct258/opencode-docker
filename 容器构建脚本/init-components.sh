#!/bin/bash
set -e

# 镜像构建期初始化脚本：只做「安装 opencode + 校验」，启动命令在 start.sh 中。
# 安装命令（官方）：curl -fsSL https://opencode.ai/install | bash
# 二进制落到 $HOME/.opencode/bin/opencode（构建期 HOME=/root）。

# 安装必要软件（curl/tar/ca-certificates：官方安装脚本所需；git：opencode 操作仓库所需；openssl：解密加密的 GitHub 令牌所需；jq：解析 JSON 所需）
apt update
apt install -y curl ca-certificates tar git jq openssl

# 安装 opencode（直接用官方一键安装命令，不锁定版本）
curl -fsSL https://opencode.ai/install | bash

# 软链到 /usr/local/bin，保证任何 PATH 下都能直接用 opencode 命令
ln -sf /root/.opencode/bin/opencode /usr/local/bin/opencode

# 校验安装
opencode --version
