# Default Dockerfile
#
# @link     https://www.hyperf.io
# @document https://hyperf.wiki
# @contact  group@hyperf.io
# @license  https://github.com/hyperf/hyperf/blob/master/LICENSE

FROM hyperf/hyperf:8.4-ubuntu-v24.04-dev
LABEL maintainer="Hyperf Developers <group@hyperf.io>" version="1.0" license="MIT" app.name="Hyperf"

ENV PHP_HOME=/usr
ENV PHPX_HOME=/opt/phpx
ENV PATH="/root/typephp:$PATH"
ENV LD_LIBRARY_PATH="$PHP_HOME/lib:$PHPX_HOME/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# 基础镜像已内置 gcc/g++/make/pkg-config 和 PHP 8.4 头文件(php8.4-dev)
# php8.4-embed 安装后 libphp.so 即位于 $PHP_HOME/lib(= /usr/lib),无需再手动拷贝
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        php8.4-embed \
        cmake \
        libgmp-dev \
        libmpfr-dev \
    && git clone https://github.com/swoole/phpx.git /opt/phpx \
    && cmake -S /opt/phpx -B /opt/phpx/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTS=OFF \
        -Dphp_dir="$PHP_HOME" \
        -DENABLE_FACADE_API=OFF \
    && cmake --build /opt/phpx/build --parallel 4 --target phpx

WORKDIR /root/typephp

COPY . .

