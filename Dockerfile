# 使用 中文Debian 作为基础镜像
FROM xct258/debian-cn

# 构建时可选锁定 opencode 版本（compose 中经 build.args 传入）
ARG OPENCODE_VERSION=""

# 构建脚本来自构建上下文（自包含；若日后推到 GitHub，可改回从 raw 拉取的 TaskOps 模式）
COPY 容器构建脚本/init-components.sh /root/tmp/init-components.sh
COPY 容器构建脚本/start.sh /usr/local/bin/start.sh

# 执行容器构建脚本（安装 opencode），随后清理临时目录
RUN chmod +x /root/tmp/init-components.sh \
    && /root/tmp/init-components.sh \
    && rm -rf /root/tmp \
    && chmod +x /usr/local/bin/start.sh

# opencode 安装目录（init 脚本已同时软链到 /usr/local/bin，双保险）
ENV PATH="/root/.opencode/bin:${PATH}"

# 设置容器启动时执行的命令
ENTRYPOINT ["/usr/local/bin/start.sh"]
