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
    build-essential git curl bash perl \
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu make nasm zip \
    libssl-dev:arm64 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# 拉取 wrk 源码
RUN git clone --depth=1 https://github.com/wg/wrk.git .

# 下载 LuaJIT 2.1.0-beta3 源码
RUN mkdir -p ThirdParty && \
    curl -L https://github.com/LuaJIT/LuaJIT/archive/v2.1.0-beta3.tar.gz | \
    tar -xz -C ThirdParty  # 移除 --strip-components=1 参数

# 交叉编译 LuaJIT 2.1.0-beta3 for ARM64 (64位)
WORKDIR /src/ThirdParty/LuaJIT-2.1  # 直接进入解压后的目录
RUN make clean || true && \
    make HOST_CC="gcc" CROSS="${CROSS_COMPILE}" TARGET_SYS=Linux TARGET=arm64 && \
    make install PREFIX=/usr/aarch64-linux-gnu

# 验证 LuaJIT 版本和架构
RUN /usr/aarch64-linux-gnu/bin/luajit --version | grep "LuaJIT 2.1.0-beta3"
RUN file /usr/aarch64-linux-gnu/bin/luajit | grep "aarch64"

# 准备 wrk 编译环境
WORKDIR /src

# 编译 wrk，明确指定 LuaJIT 相关参数
RUN make clean || true && \
    make CC=${CC} \
         WITH_LUAJIT=/usr/aarch64-linux-gnu \
         LDFLAGS="-L/usr/aarch64-linux-gnu/lib -Wl,-rpath,/usr/aarch64-linux-gnu/lib" \
         CFLAGS="-I/usr/aarch64-linux-gnu/include/luajit-2.1 -I/usr/aarch64-linux-gnu/include" \
         SSL_INC="/usr/include/aarch64-linux-gnu" \
         SSL_LIB="/usr/lib/aarch64-linux-gnu"

# 提取必要的依赖库
RUN mkdir -p /deps && \
    ${CROSS_COMPILE}strip wrk && \
    cp wrk /deps/ && \
    ldd wrk | grep "=> /" | awk '{print $3}' | xargs -I '{}' cp -v '{}' /deps/ || true

###############################################################################
# Stage 2: Runtime (Alpine, 极简运行镜像)
###############################################################################
FROM alpine:3.19

# 安装必要的基础库
RUN apk add --no-cache libgcc libstdc++ openssl

# 复制编译好的 wrk 和依赖库
COPY --from=builder /deps/ /usr/local/bin/

# 验证 LuaJIT 集成和架构
RUN /usr/local/bin/wrk -v | grep "LuaJIT"
RUN file /usr/local/bin/wrk | grep "aarch64"

ENTRYPOINT ["/usr/local/bin/wrk"]
CMD ["--help"]
