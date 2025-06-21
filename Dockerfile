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

# 在 /src 目录下生成 luajit.zip，Makefile 会用它
WORKDIR /src
RUN mkdir -p deps/ThirdParty/LuaJIT-2.1/src && \
    cp ThirdParty/LuaJIT-2.1/src/luajit deps/ThirdParty/LuaJIT-2.1/src/luajit.bin && \
    cd deps/ThirdParty/LuaJIT-2.1/src && \
    zip luajit.zip luajit.bin

# 编译 wrk，确保使用正确的路径，不会拼接多余的 deps/ 前缀
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
