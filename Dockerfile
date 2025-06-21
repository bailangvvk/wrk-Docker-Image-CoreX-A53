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

# 交叉编译 LuaJIT 2.1.0-beta3（确保生成 ARM64 架构）
WORKDIR /src/ThirdParty/LuaJIT-2.1.0-beta3
RUN make clean || true && \
    # 主机工具使用宿主机编译器，目标程序使用交叉编译器
    make HOST_CC="gcc" CROSS="${CROSS_COMPILE}" TARGET_SYS=Linux ARCH=arm64 && \
    make install PREFIX=/usr && \
    ln -sf /usr/bin/luajit-2.1.0-beta3 /usr/bin/luajit

# 编译前验证LuaJIT
RUN export PATH="/usr/bin:$PATH" && \
    echo "=== 验证LuaJIT安装 ===" && \
    luajit -v && \
    luajit -e "require('jit')" || (echo "LuaJIT模块缺失" && exit 1) && \

# 编译wrk前的详细调试检查
WORKDIR /src
RUN export PATH="/usr/bin:$PATH" && \
    # 1. 打印关键环境变量
    echo "=== 编译环境变量 ===" && \
    env | grep -E "PATH|WITH_LUAJIT|SSL_INC|SSL_LIB|CC|LDFLAGS|CFLAGS" && \
    
    # 2. 检查头文件和库文件存在性（增强调试）
    echo "=== LuaJIT头文件 ===" && \
    ls -la /usr/include/luajit-2.1/ | grep -E "lua.h|luajit.h" && \
    
    echo "=== 实际OpenSSL头文件路径检查 ===" && \
    # 检查标准路径和架构路径
    ls -la /usr/include/openssl/ || ls -la /usr/include/aarch64-linux-gnu/openssl/ || \
    (echo "OpenSSL头文件未找到" && exit 1) && \
    
    echo "=== OpenSSL库文件检查 ===" && \
    ls -la /usr/lib/aarch64-linux-gnu/libssl* /usr/lib/aarch64-linux-gnu/libcrypto* || \
    ls -la /usr/lib/libssl* /usr/lib/libcrypto*

# 编译wrk（修正LuaJIT路径）
RUN export PATH="/usr/bin:$PATH" && \
    make clean || true && \
    make CC=aarch64-linux-gnu-gcc \
         WITH_LUAJIT=/usr \
         CFLAGS="-I/usr/include/luajit-2.1 -I/usr/include" \
         LDFLAGS="-L/usr/lib/aarch64-linux-gnu -Wl,-rpath,/usr/lib/aarch64-linux-gnu -lssl -lcrypto" \
         SSL_INC="/usr/include" \
         SSL_LIB="/usr/lib/aarch64-linux-gnu" \
         V=1

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

# 安装最小化运行时依赖
RUN apk add --no-cache \
    libgcc libstdc++ \
    openssl  # 或使用 libssl3 libcrypto3，根据 Alpine 3.19 实际包名

# 复制编译好的 wrk 和依赖库
COPY --from=builder /deps/ /usr/local/bin/

# 同步 LuaJIT 模块
COPY --from=builder /usr/share/luajit-2.1.0-beta3/jit/ /usr/local/share/luajit-2.1.0-beta3/jit/
COPY --from=builder /usr/lib/lua/5.1/ /usr/local/lib/lua/5.1/

# 验证镜像
RUN /usr/local/bin/wrk -v | grep "LuaJIT" && \
    file /usr/local/bin/wrk | grep "aarch64" && \
    # 验证 OpenSSL 库
    ls -la /lib/libssl* /lib/libcrypto* && \
    # 验证 LuaJIT jit 模块
    /usr/local/bin/luajit -e "require('jit') print('JIT module loaded')"

ENTRYPOINT ["/usr/local/bin/wrk"]
CMD ["--help"]
