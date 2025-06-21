FROM --platform=linux/arm64 ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y build-essential git curl make \
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu perl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src

# 获取 wrk 和 LuaJIT
RUN git clone https://github.com/wg/wrk.git . && \
    mkdir -p ThirdParty && \
    git clone -b v2.1 https://github.com/LuaJIT/LuaJIT.git ThirdParty/LuaJIT-2.1

# 构建 LuaJIT for ARM64
WORKDIR /src/ThirdParty/LuaJIT-2.1
RUN make clean || true && \
    make CROSS=aarch64-linux-gnu- TARGET=arm64 HOST_CC=gcc

# 构建 wrk（使用交叉编译后的 LuaJIT 二进制）
WORKDIR /src
RUN make clean || true && \
    make CC=aarch64-linux-gnu-gcc LUAJIT=ThirdParty/LuaJIT-2.1/src/luajit

# 生成最终镜像
FROM --platform=linux/arm64 scratch AS final
COPY --from=builder /src/wrk /usr/bin/wrk
ENTRYPOINT ["/usr/bin/wrk"]
