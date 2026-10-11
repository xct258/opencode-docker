# OpenCode 容器

与 TaskOps 同思路的单容器项目：镜像构建期装好 `opencode`，容器启动时跑
`opencode web --hostname 0.0.0.0`，浏览器打开即可用。适合内网/个人服务器部署，
配合反向代理对外提供单一域名。

---

## 一、架构与端口

| 组件 | 说明 | 监听 | 对外 |
| --- | --- | --- | --- |
| opencode web | AI 编程 web 界面 | `4096`（`PORT` 可改） | 经反代 |

---

## 二、目录结构

```
容器构建脚本/
├── init-components.sh # 镜像构建期：装依赖 + 官方脚本安装 opencode + 校验
├── start.sh           # 容器启动：解密 GitHub 令牌配 git 推送、在 /app/workspace 起 web 服务
└── encrypt-token.sh   # 宿主机加密 GitHub Token 为 加密令牌/github_token.enc 的 helper
加密令牌/
├── README.md          # 本目录说明（只放密文）
└── github_token.enc   # 加密后的令牌（密文随项目提交，密码正确才能解密用于 git 推送）
Dockerfile             # 仅供 GitHub Actions 构建镜像，本地不构建（镜像内不含令牌）
docker-compose.yml     # 纯运行配置（无 build，仅 pull 镜像 + host 网络 + 数据卷 + 令牌只读挂载）
.github/workflows/docker-image.yml # 唯一构建入口：多架构构建并推送到 Docker Hub
workspace/             # 工作目录：web 会话的操作目录（随卷持久化，git 推送即在此执行）
config/                # opencode 配置（opencode.json 等，挂到 /root/.config/opencode）
data/                  # 会话数据（挂到 /root/.local/share/opencode）
```

---

## 三、快速开始

### 1. 镜像构建（仅 GitHub Actions，本地不构建）

镜像 `xct258/opencode:latest` 只由 `.github/workflows/docker-image.yml` 构建并推送到 Docker Hub，
多架构 `linux/amd64,linux/arm64`。

触发条件：

- `push` 到 `main` 且改动 `Dockerfile` / `容器构建脚本/**` / 工作流本身
- 每月 1 日定时 `cron: '0 0 1 * *'`
- 手动 `workflow_dispatch`

`Dockerfile` 会 `COPY` 构建脚本并执行 `init-components.sh`：安装
`curl / git / jq` 等依赖，直接用官方一键安装命令 `curl -fsSL https://opencode.ai/install | bash`
安装 opencode（落到 `/root/.opencode/bin`，并软链到 `/usr/local/bin`，不锁定版本）。

### 2. 启动（纯 pull 运行）

```bash
# 建议先设置 web 访问密码（走 0.0.0.0 对外时官方要求鉴权）
export OPENCODE_SERVER_PASSWORD=你的密码
docker compose pull
docker compose up -d
```

`docker-compose.yml`（无 `build`，只用预构建镜像）：

```yaml
services:
  opencode:
    container_name: opencode
    image: xct258/opencode
    network_mode: host        # 直接占用宿主机 4096（或 PORT 指定端口）
    volumes:
      - ./workspace:/app/workspace
      - ./config:/root/.config/opencode
      - ./data:/root/.local/share/opencode
      - ./加密令牌:/secrets:ro
    environment:
      - PORT=${PORT:-4096}
      - OPENCODE_SERVER_PASSWORD=${OPENCODE_SERVER_PASSWORD:-}
      - GITHUB_TOKEN_PASSWORD=${GITHUB_TOKEN_PASSWORD:-}
      - GITHUB_TOKEN_FILE=${GITHUB_TOKEN_FILE:-/secrets/github_token.enc}
    restart: always
```

### 3. 访问

- 内网直连：`http://<主机>:4096`（用户名 `opencode` + 上面设置的密码）
- 经反代：`https://opencode.你的域名.com`（推荐，见第六节）

---

## 四、容器启动流程

`docker compose up` 后执行 `ENTRYPOINT` 即 `/usr/local/bin/start.sh`：

1. 建持久化目录 `/app/workspace`、`~/.config/opencode`、`~/.local/share/opencode`。
2. 未设 `OPENCODE_SERVER_PASSWORD` 时打警告（无鉴权，仅限内网）。
3. 若存在加密令牌（默认 `/secrets/github_token.enc`，即项目内 `./加密令牌/github_token.enc` 只读挂载；
   兼容旧位置 `~/.config/opencode/.github_token.enc`），
   用 `GITHUB_TOKEN_PASSWORD`（未设则复用 `OPENCODE_SERVER_PASSWORD`）经
   `openssl enc -d -aes-256-cbc -pbkdf2` 解密：
   - 密码错误 / 未设密码 → 直接 `exit 1` 拒绝启动，容器起不来，令牌不会被使用；
   - 解密成功 → 配置 `git credential.helper`（HTTPS 推送免密，文件内仅 github.com 记录），
     并导出 `GITHUB_TOKEN` / `GH_TOKEN` 供 `gh` 与 opencode 复用，
     再 `cd /app/workspace` 前台执行 `opencode web --hostname 0.0.0.0 --port 4096`
     （它是容器主进程，退出即容器停止，退出时 trap 自动删除 `/root/.git-credentials` 并清理内存明文）。
4. 若无加密文件且无明文 `GITHUB_TOKEN`，则打印提示后直接启动（git 推送需手动鉴权）。

---

## 五、GitHub 令牌加密存储（密码正确才用于 git 推送）

原理：`openssl enc -aes-256-cbc -pbkdf2 -salt` 对称加密，密码即密钥。密文存项目内
`./加密令牌/github_token.enc` 并随仓库提交（无密码无法解密）；镜像内不含令牌，换令牌无需重打镜像。
容器启动时才在内存中解密，配置 `git credential.helper` 供 `/app/workspace` 内的 `git push` 使用，
明文不落盘（`git-credentials` 仅存于容器覆盖层，退出自动删）。

### 加密（宿主机执行一次，密文提交到项目）

```bash
bash "容器构建脚本/encrypt-token.sh"
# 按提示粘贴 Token，再输两次密码（建议与 OPENCODE_SERVER_PASSWORD 相同，单密码模式）
# 生成文件（权限 600）：./加密令牌/github_token.enc，git add 提交即可
```

### 使用

```bash
# 单密码模式：解密密码复用 web 密码，输错密码容器拒绝启动，令牌不会被使用
export OPENCODE_SERVER_PASSWORD=你的密码
docker compose pull && docker compose up -d

# 独立密码模式：web 密码与令牌密码分开
export OPENCODE_SERVER_PASSWORD=web密码
export GITHUB_TOKEN_PASSWORD=加密时设的密码
docker compose up -d
```

### 验证推送

```bash
# 容器内执行：密码正确则免密通过，错误/缺密码则容器根本起不来
docker exec opencode git -C /app/workspace ls-remote https://github.com/<owner>/<repo>.git HEAD
# 日常使用：在 /app/workspace 内 git push，无需再输令牌
```

| 场景 | 行为 |
| --- | --- |
| 密码正确 | 解密成功，`git push` 免密（另附 `GITHUB_TOKEN`/`GH_TOKEN` 供 `gh`/opencode 复用） |
| 密码错误 | 日志 `GitHub 令牌解密失败，密码不正确`，容器退出码 1，起不来，令牌不可用 |
| 有加密文件但没给密码 | 日志提示缺密码，容器退出码 1 |
| 无加密文件 | 正常启动，提示 git 推送需手动鉴权 |

> 注意：换 `OPENCODE_SERVER_PASSWORD` 前，先用旧密码解密出 Token，再用新密码重新加密，
> 否则单密码模式下换密码即换密钥，旧加密文件将无法解密。

---

## 六、反向代理（Nginx Proxy Manager）

opencode 用 `network_mode: host`，端口在宿主机上。NPM 配置参考 TaskOps：

**Proxy Host**

| 项 | 值 |
| --- | --- |
| Domain Names | `opencode.你的域名.com` |
| Scheme | `http` |
| Forward Hostname / IP | `127.0.0.1`（NPM 在 bridge 网络时用 `host.docker.internal`） |
| Forward Port | `4096` |
| SSL | 申请 Let's Encrypt，开启 Force SSL |

> NPM 在 bridge 网络里时记得加 `extra_hosts: ["host.docker.internal:host-gateway"]`。

---

## 七、数据持久化与升级

- 工作文件在 `./workspace`，配置在 `./config`，会话数据在 `./data`，重建/升级容器不丢。
- 升级 opencode：等 GitHub Actions 重打镜像并推送到 `xct258/opencode:latest` 后，本地只需
  `docker compose pull && docker compose up -d`，卷内数据不受影响，本地不执行构建。

---

## 八、注意事项

- 不设密码时 web 无鉴权，**仅限内网使用，不要直接暴露公网**；对外请设
  `OPENCODE_SERVER_PASSWORD` 并走反代加 HTTPS。
- 加密令牌 `./加密令牌/github_token.enc` 是密文，随项目提交无妨，但权限保持 600；
  明文 Token 和密码绝不进仓库，`encrypt-token.sh` 只经 stdin 读取、不落盘。
- `opencode web` 默认随机端口，本项目固定为 `4096`（`PORT` 环境变量可改）。
- 模型鉴权（各家 API key）在 web 界面或 `config/opencode.json` 里配一次即可持久化。
