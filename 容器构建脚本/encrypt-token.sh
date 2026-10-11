#!/bin/bash
set -e
# 用法：
#   ./encrypt-token.sh [输出文件]
#   先粘贴 GitHub Token，再输入两次密码（默认与 OPENCODE_SERVER_PASSWORD 相同，实现单密码解锁）。
#   输出文件默认 ./加密令牌/github_token.enc（随项目提交密文；容器内挂载为 /secrets/github_token.enc，只读）
# 加密算法：openssl enc -aes-256-cbc -pbkdf2 -salt，与 start.sh 解密端严格对应。

OUT_FILE="${1:-./加密令牌/github_token.enc}"

echo "请输入 GitHub Token（输入时不可见，粘贴后回车）："
read -rs GITHUB_TOKEN_INPUT
echo
if [ -z "$GITHUB_TOKEN_INPUT" ]; then
    echo "错误：Token 为空，已取消" >&2
    exit 1
fi

echo "请输入加密密码（建议与 OPENCODE_SERVER_PASSWORD 相同）："
read -rs PASSWORD_ONE
echo
echo "请再次输入密码确认："
read -rs PASSWORD_TWO
echo
if [ -z "$PASSWORD_ONE" ]; then
    echo "错误：密码为空，已取消" >&2
    exit 1
fi
if [ "$PASSWORD_ONE" != "$PASSWORD_TWO" ]; then
    echo "错误：两次密码不一致，已取消" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUT_FILE")"
# PASSWORD_ONE 需 export 才能被 openssl 的 -pass env: 读取；子 shell 内 export，不污染父环境
printf '%s' "$GITHUB_TOKEN_INPUT" | (export PASSWORD_ONE; openssl enc -e -aes-256-cbc -pbkdf2 -salt -out "$OUT_FILE" -pass env:PASSWORD_ONE)
chmod 600 "$OUT_FILE"

# 立即清理内存中的明文
unset GITHUB_TOKEN_INPUT PASSWORD_ONE PASSWORD_TWO

echo "已加密保存到 $OUT_FILE（权限 600），随项目提交密文即可"
echo "容器启动时设置相同密码即可解密并用于 git 推送：OPENCODE_SERVER_PASSWORD=你的密码 docker compose up -d"
echo "若需独立密码，则设置 GITHUB_TOKEN_PASSWORD=加密密码"
