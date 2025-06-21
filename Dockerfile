# syntax=docker/dockerfile:1.4

###############################################################################
# Stage 1: Builder (Ubuntu, cross-compile wrk + LuaJIT for ARM64)
###############################################################################
FROM ubuntu:22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive

# 安装交叉编译工具及依赖
RUN apt-get update && apt-get install -y \
    build-essential git curl bash perl \
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu make nasm zip \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# 拉取 wrk 源码
RUN git clone --depth=1 https://github.com/wg/wrk.git .

# 拉取 LuaJIT 源码到 ThirdParty
RUN mkdir -p ThirdParty && \
    git clone --depth=1 --branch v2.1 https://github.com/LuaJIT/LuaJIT.git ThirdParty/LuaJIT-2.1

# 交叉编译 LuaJIT for ARM64
WORKDIR /src/ThirdParty/LuaJIT-2.1
RUN make clean || true && \
    make CROSS=aarch64-linux-gnu- TARGET=ARM64 HOST_CC=gcc

# 切回 wrk 源码根目录
WORKDIR /src

# DEBUG STEP: 打印当前路径、目录结构、Makefile 中的 LUAJIT 相关片段
RUN echo "=== DEBUG: CURRENT DIR ===" && pwd && \
    echo "=== DEBUG: RECURSIVE LS ===" && ls -R . && \
    echo "=== DEBUG: ENV LUAJIT VAR ===" && \
      echo "LUAJIT set to: $LUAJIT" || true && \
    echo "=== DEBUG: Makefile LUAJIT references ===" && \
      grep -R "LUAJIT" Makefile || true

# DEBUG STEP: 检查 deps 目录下的文件
RUN echo "=== DEBUG: deps directory ===" && ls -R deps/ThirdParty/LuaJIT-2.1/src || true

# 真正编译 wrk
RUN make clean || true && \
    make CC=aarch64-linux-gnu-gcc LUAJIT=deps/ThirdParty/LuaJIT-2.1/src/luajit.zip

###############################################################################
# Stage 2: Runtime (Alpine, 极简运行镜像)
###############################################################################
FROM alpine:3.19

# 直接复制编译好的 wrk 二进制
COPY --from=builder /src/wrk /usr/local/bin/wrk

ENTRYPOINT ["/usr/local/bin/wrk"]
CMD ["--help"]
