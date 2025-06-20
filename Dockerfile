FROM ubuntu:22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    build-essential git curl bash perl \
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu make nasm zip \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /src

RUN git clone --depth=1 https://github.com/wg/wrk.git . && \
    git clone --depth=1 --branch v2.1 https://github.com/LuaJIT/LuaJIT.git ThirdParty/LuaJIT-2.1

# 编译 LuaJIT
WORKDIR /src/ThirdParty/LuaJIT-2.1
RUN make clean || true && \
    make CROSS=aarch64-linux-gnu- TARGET=ARM64 HOST_CC=gcc

# 回到 wrk 源码根目录，生成 luajit.zip
WORKDIR /src
RUN mkdir -p deps/ThirdParty/LuaJIT-2.1/src && \
    cp ThirdParty/LuaJIT-2.1/src/luajit deps/ThirdParty/LuaJIT-2.1/src/luajit.bin && \
    cd deps/ThirdParty/LuaJIT-2.1/src && \
    zip luajit.zip luajit.bin

# 编译 wrk
RUN make clean || true && \
    make CC=aarch64-linux-gnu-gcc LUAJIT=deps/ThirdParty/LuaJIT-2.1/src/luajit.zip

# 最终运行镜像
FROM alpine:3.19
COPY --from=builder /src/wrk /usr/local/bin/wrk
ENTRYPOINT ["/usr/local/bin/wrk"]
CMD ["--help"]
