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
└── start.sh           # 容器启动：建持久化目录、在 /app/workspace 起 web 服务
Dockerfile             # 基于 xct258/debian-cn 构建镜像
docker-compose.yml     # 运行容器（host 网络 + 三个数据卷）
workspace/             # 工作目录：web 会话的操作目录（随卷持久化）
config/                # opencode 配置（opencode.json 等，挂到 /root/.config/opencode）
data/                  # 会话数据（挂到 /root/.local/share/opencode）
```

---

## 三、快速开始

### 1. 构建镜像

```bash
docker build -t xct258/opencode .
```

`Dockerfile` 会 `COPY` 构建脚本并执行 `init-components.sh`：安装
`curl / git / jq` 等依赖，用官方命令 `curl -fsSL https://opencode.ai/install | bash`
安装 opencode（落到 `/root/.opencode/bin`，并软链到 `/usr/local/bin`）。

> 锁定版本：`OPENCODE_VERSION=0.5.0 docker build --build-arg OPENCODE_VERSION=0.5.0 -t xct258/opencode .`

### 2. 启动

```bash
# 建议先设置 web 访问密码（走 0.0.0.0 对外时官方要求鉴权）
export OPENCODE_SERVER_PASSWORD=你的密码
docker compose up -d
```

`docker-compose.yml`：

```yaml
services:
  opencode:
    container_name: opencode
    image: xct258/opencode
    network_mode: host        # 直接占用宿主机 4096
    volumes:
      - ./workspace:/app/workspace
      - ./config:/root/.config/opencode
      - ./data:/root/.local/share/opencode
    restart: always
```

### 3. 访问

- 内网直连：`http://<主机>:4096`（用户名 `opencode` + 上面设置的密码）
- 经反代：`https://opencode.你的域名.com`（推荐，见第五节）

---

## 四、容器启动流程

`docker compose up` 后执行 `ENTRYPOINT` 即 `/usr/local/bin/start.sh`：

1. 建持久化目录 `/app/workspace`、`~/.config/opencode`、`~/.local/share/opencode`。
2. 未设 `OPENCODE_SERVER_PASSWORD` 时打警告（无鉴权，仅限内网）。
3. `cd /app/workspace`，前台执行 `opencode web --hostname 0.0.0.0 --port 4096`
   （它是容器主进程，退出即容器停止）。

---

## 五、反向代理（Nginx Proxy Manager）

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

## 六、数据持久化与升级

- 工作文件在 `./workspace`，配置在 `./config`，会话数据在 `./data`，重建/升级容器不丢。
- 升级 opencode：重打镜像（`docker build` 会装最新版，或用 `OPENCODE_VERSION` 锁定），
  `docker compose up -d` 即可，卷内数据不受影响。

---

## 七、注意事项

- 不设密码时 web 无鉴权，**仅限内网使用，不要直接暴露公网**；对外请设
  `OPENCODE_SERVER_PASSWORD` 并走反代加 HTTPS。
- `opencode web` 默认随机端口，本项目固定为 `4096`（`PORT` 环境变量可改）。
- 模型鉴权（各家 API key）在 web 界面或 `config/opencode.json` 里配一次即可持久化。
