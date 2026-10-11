# 加密后的 GitHub 令牌存放目录（随项目提交）

- 本目录只放 **密文**（`*.enc`，`openssl enc -aes-256-cbc -pbkdf2` 加密），**绝不放明文 Token 和密码**。
- 密文可随仓库提交：没有密码无法解密，容器启动时凭密码在内存中解密，仅用于 `git 推送`
  （`credential.helper` + `GITHUB_TOKEN`/`GH_TOKEN`），密码错误则容器拒绝启动。
- 生成密文：`bash "容器构建脚本/encrypt-token.sh"`（默认输出到本目录 `github_token.enc`）。
- 容器内挂载路径：`/secrets`（只读），见 `docker-compose.yml`。
