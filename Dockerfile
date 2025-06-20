# 使用适合的基础镜像
FROM --platform=linux/amd64 alpine:3.19 AS build

# 安装构建工具
RUN apk update && apk add --no-cache \
    build-base \
    git \
    clang \
    llvm \
    make \
    gcc \
    g++ \
    nasm \
    qemu-user-static \
    libffi-dev \
    libgcc \
    linux-headers \
    curl \
    bash \
    && rm -rf /var/cache/apk/*

# 克隆 wrk 和 LuaJIT 源码
WORKDIR /wrk
RUN git clone https://github.com/wg/wrk.git .

# 构建 wrk 所需的 LuaJIT
WORKDIR /wrk/obj
RUN git clone https://github.com/LuaJIT/LuaJIT.git LuaJIT-2.1
WORKDIR /wrk/obj/LuaJIT-2.1
RUN make -j$(nproc) && make install

# 构建 wrk
WORKDIR /wrk
RUN make -j$(nproc)

# 创建最终的镜像
FROM alpine:3.19
RUN apk add --no-cache libgcc

# 将编译的 wrk 拷贝到最终镜像
COPY --from=build /wrk/wrk /usr/local/bin/

# 设置默认命令
ENTRYPOINT ["/usr/local/bin/wrk"]
CMD ["--help"]
