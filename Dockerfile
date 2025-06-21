# syntax=docker/dockerfile:1.4

###############################################################################
# Stage 1: Builder (Ubuntu, cross-compile wrk + LuaJIT 2.1.0-beta3 for ARM64)
###############################################################################
FROM ubuntu:22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive
ENV TARGETARCH=arm64
ENV CROSS_COMPILE=aarch64-linux-gnu-
ENV CC=${CROSS_COMPILE}gcc
ENV LD=${CROSS_COMPILE}ld
ENV STRIP=${CROSS_COMPILE}strip
# 新增：设置 Lua 环境变量，确保找到 jit 模块
ENV LUA_PATH="/usr/aarch64-linux-gnu/share/luajit-2.1.0-beta3/jit/?.lua;;"
ENV LUA_CPATH="/usr/aarch64-linux-gnu/lib/lua/5.1/?.so;;"

# 安装交叉编译工具及依赖
RUN apt-get update && apt-get install -y \
    build-essential git curl make nasm zip \
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
    libssl-dev:arm64 file \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# 拉取 wrk 源码
RUN git clone --depth=1 https://github.com/wg/wrk.git .

# 下载 LuaJIT 2.1.0-beta3 源码
RUN mkdir -p ThirdParty && \
    git clone --depth=1 --branch v2.1.0-beta3 https://github.com/LuaJIT/LuaJIT.git ThirdParty/LuaJIT-2.1.0-beta3

# 交叉编译 LuaJIT 2.1.0-beta3（修改安装路径）
WORKDIR /src/ThirdParty/LuaJIT-2.1.0-beta3
RUN make clean || true && \
    make HOST_CC="gcc" CROSS="${CROSS_COMPILE}" TARGET_SYS=Linux TARGET=arm64 && \
    # 安装到系统默认路径，避免路径问题
    make install PREFIX=/usr && \
    # 创建符号链接
    ln -sf /usr/bin/luajit-2.1.0-beta3 /usr/bin/luajit

# 验证 LuaJIT 安装
RUN /usr/bin/luajit -v | grep "LuaJIT 2.1.0-beta3" && \
    file /usr/bin/luajit | grep "aarch64" && \
    # 检查 jit 模块是否存在
    ls -la /usr/share/luajit-2.1.0-beta3/jit/

# 验证 LuaJIT 安装（版本和模块路径）
RUN /usr/aarch64-linux-gnu/bin/luajit -v | grep "LuaJIT 2.1.0-beta3"
RUN file /usr/aarch64-linux-gnu/bin/luajit | grep "aarch64"
RUN ls -la /usr/aarch64-linux-gnu/share/luajit-2.1.0-beta3/jit/  # 检查 jit 模块是否存在

# 编译 wrk（简化环境变量，使用系统默认路径）
WORKDIR /src
RUN export PATH="/usr/bin:$PATH" && \
    echo "=== 编译wrk前的PATH ===" && echo $PATH && \
    which luajit && luajit -v && \
    # 验证 jit 模块可访问
    luajit -e "require('jit') print('JIT module loaded')" && \
    make clean || true && \
    make CC=${CC} \
         WITH_LUAJIT=/usr \
         LDFLAGS="-L/usr/lib -Wl,-rpath,/usr/lib" \
         CFLAGS="-I/usr/include/luajit-2.1 -I/usr/include/aarch64-linux-gnu" \
         SSL_INC="/usr/include/aarch64-linux-gnu" \
         SSL_LIB="/usr/lib/aarch64-linux-gnu"

# 提取必要的依赖库
RUN mkdir -p /deps && \
    ${CROSS_COMPILE}strip wrk && \
    cp wrk /deps/ && \
    ldd wrk | grep "=> /" | awk '{print $3}' | \
    xargs -I '{}' cp -v '{}' /deps/ || true

###############################################################################
# Stage 2: Runtime (Alpine, 极简运行镜像)
###############################################################################
FROM alpine:3.19

# 安装最小化运行时依赖（修正包名）
RUN apk add --no-cache \
    libgcc libstdc++ \
    openssl

# 复制编译好的 wrk 和依赖库
COPY --from=builder /deps/ /usr/local/bin/

# 同步 LuaJIT 模块（确保 jit 可用）
COPY --from=builder /usr/aarch64-linux-gnu/share/luajit-2.1.0-beta3/jit/ /usr/local/share/luajit-2.1.0-beta3/jit/
COPY --from=builder /usr/aarch64-linux-gnu/lib/lua/5.1/ /usr/local/lib/lua/5.1/

# 验证镜像（新增 OpenSSL 库检查）
RUN /usr/local/bin/wrk -v | grep "LuaJIT" && \
    file /usr/local/bin/wrk | grep "aarch64" && \
    echo "=== OpenSSL 库检查 ===" && \
    ls -la /lib/libssl* /lib/libcrypto* && \
    # 验证 LuaJIT jit 模块
    /usr/local/bin/luajit -e "require('jit') print('JIT module loaded')"

ENTRYPOINT ["/usr/local/bin/wrk"]
CMD ["--help"]
