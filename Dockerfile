# 第一阶段：构建阶段，安装交叉编译工具，编译 LuaJIT 和 wrk
FROM alpine:3.19 AS builder

RUN apk add --no-cache \
    build-base git clang llvm make gcc g++ nasm curl bash perl \
    aarch64-linux-gnu-gcc aarch64-linux-gnu-g++ linux-headers

WORKDIR /build

# 克隆 wrk 和 LuaJIT
RUN git clone https://github.com/wg/wrk.git && \
    git clone --branch v2.1 https://github.com/LuaJIT/LuaJIT.git wrk/ThirdParty/LuaJIT-2.1.0-beta3

# 编译 LuaJIT for ARM64
WORKDIR /build/wrk/ThirdParty/LuaJIT-2.1.0-beta3
RUN sed -i 's/^TARGET=.*$/TARGET=ARM64/' Makefile && \
    make clean || true && \
    make CROSS=aarch64-linux-gnu- TARGET=ARM64 HOST_CC=gcc

# 编译 wrk，使用刚编译的 LuaJIT
WORKDIR /build/wrk
RUN make clean || true && \
    make CC=aarch64-linux-gnu-gcc LUAJIT=ThirdParty/LuaJIT-2.1.0-beta3/src/luajit

# 第二阶段：生成最小运行镜像
FROM alpine:3.19

COPY --from=builder /build/wrk/wrk /usr/local/bin/wrk

ENTRYPOINT ["/usr/local/bin/wrk"]
CMD ["--help"]
