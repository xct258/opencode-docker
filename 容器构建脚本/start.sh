#!/bin/bash
set -e

# 持久化目录（对应 compose 中的挂载卷；config/data 缺省由 opencode 自行生成）
mkdir -p /app/workspace /root/.config/opencode /root/.local/share/opencode

# opencode web 默认随机端口，容器内固定为 $PORT（默认 4096），便于映射与反代
PORT="${PORT:-4096}"

# 经网络访问时官方要求设置鉴权；未设置则无密码，仅限内网使用
if [ -z "${OPENCODE_SERVER_PASSWORD:-}" ]; then
    echo "警告：未设置 OPENCODE_SERVER_PASSWORD，web 界面无鉴权，仅限内网使用" >&2
fi

# ---- 加密 GitHub 令牌：只有启动密码正确才解密用于 git 推送 ----
# 约定：
#   加密文件默认：/secrets/github_token.enc（宿主机项目内 ./加密令牌/github_token.enc，只读挂载，密文随仓库提交）
#   解密密码优先用 GITHUB_TOKEN_PASSWORD，未设置则复用 OPENCODE_SERVER_PASSWORD（单密码模式）
#   解密成功后配置 git credential.helper（HTTPS 推送免密）并导出 GITHUB_TOKEN / GH_TOKEN；
#   密码错误 / 未设密码：不拒绝启动容器，跳过令牌，不配置 git，并删除已有凭证文件
TOKEN_FILE="${GITHUB_TOKEN_FILE:-/secrets/github_token.enc}"
# 兼容旧位置（config 卷内），仅当未显式指定文件且新位置不存在时回落
if [ ! -f "$TOKEN_FILE" ] && [ -z "${GITHUB_TOKEN_FILE:-}" ] && [ -f /root/.config/opencode/.github_token.enc ]; then
    TOKEN_FILE="/root/.config/opencode/.github_token.enc"
fi
TOKEN_PASSWORD="${GITHUB_TOKEN_PASSWORD:-${OPENCODE_SERVER_PASSWORD:-}}"

cleanup_sensitive() {
    # 退出时清理内存中的明文与 git 凭证文件，避免落盘残留
    # 注意：GITHUB_TOKEN/GH_TOKEN 需保留给 opencode 子进程，故不在此处 unset
    unset DECRYPTED_TOKEN TOKEN_PASSWORD 2>/dev/null || true
    rm -f /root/.git-credentials 2>/dev/null || true
}
trap cleanup_sensitive EXIT HUP INT TERM

# 密码错误 / 未设密码：不拒绝启动容器，而是跳过令牌（不解密、不配置 git），删除已有凭证文件
if [ -f "$TOKEN_FILE" ]; then
    if [ -n "${TOKEN_PASSWORD:-}" ]; then
        if DECRYPTED_TOKEN="$(export TOKEN_PASSWORD; openssl enc -d -aes-256-cbc -pbkdf2 -in "$TOKEN_FILE" -pass env:TOKEN_PASSWORD 2>/dev/null)"; then
            if [ -n "$DECRYPTED_TOKEN" ]; then
                # 解密成功：配置 git 推送并导出 token
                export GITHUB_TOKEN="$DECRYPTED_TOKEN"
                export GH_TOKEN="$DECRYPTED_TOKEN"
                printf 'https://oauth2:%s@github.com\n' "$DECRYPTED_TOKEN" > /root/.git-credentials
                chmod 600 /root/.git-credentials
                git config --global credential.helper 'store --file /root/.git-credentials'
                unset DECRYPTED_TOKEN
                echo "GitHub 令牌解密成功，git 推送已就绪（退出后凭证自动清理）"
            else
                # 结果为空：视为解密失败（密码可能不完全正确），删除已有凭证文件，不使用令牌
                rm -f /root/.git-credentials 2>/dev/null || true
                echo "警告：令牌解密结果为空，未使用 GitHub 令牌，容器正常启动（git 推送需手动鉴权）" >&2
            fi
        else
            # openssl 解密失败（密码错误）：删除已有凭证文件，不使用令牌，正常启动
            rm -f /root/.git-credentials 2>/dev/null || true
            echo "警告：密码不正确，未解密 GitHub 令牌，已删除凭证文件，容器正常启动（git 推送需手动鉴权）" >&2
        fi
    else
        # 有加密文件但没有提供密码：删除已有凭证文件，不使用令牌，正常启动
        rm -f /root/.git-credentials 2>/dev/null || true
        echo "警告：未提供解密密码，未使用 GitHub 令牌，已删除凭证文件，容器正常启动（git 推送需手动鉴权）" >&2
    fi
else
    # 无加密文件时：若直接给了明文 GITHUB_TOKEN（临时调试），仅警告后透传，不落盘
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        echo "警告：使用明文 GITHUB_TOKEN 环境变量，建议改用加密文件 $TOKEN_FILE" >&2
        export GH_TOKEN="${GH_TOKEN:-$GITHUB_TOKEN}"
    else
        echo "提示：未检测到加密令牌 $TOKEN_FILE，容器正常启动，但 git 推送需手动鉴权"
    fi
fi

# 在工作目录启动，web 会话默认落到该目录
cd /app/workspace

# 前台启动（它是容器主进程，退出即容器停止；exec 会替换进程，trap EXIT 仍会在容器停止时执行）
exec opencode web --hostname 0.0.0.0 --port "$PORT"
