# Default Dockerfile
#
# @link     https://www.hyperf.io
# @document https://hyperf.wiki
# @contact  group@hyperf.io
# @license  https://github.com/hyperf/hyperf/blob/master/LICENSE

FROM hyperf/hyperf:8.4-zts-ubuntu-v24.04-dev
LABEL maintainer="Hyperf Developers <group@hyperf.io>" version="1.0" license="MIT" app.name="Hyperf"

ENV PHP_HOME=/usr/local
ENV PHPX_HOME=/opt/phpx
ENV PATH="/root/typephp:$PATH"
ENV LD_LIBRARY_PATH="$PHP_HOME/lib:$PHPX_HOME/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
ENV TYPEPHP_VERSION="v0.9.3"
ENV PHP_VERSION="8.4.26"

# 基础镜像已内置 gcc/g++/make/pkg-config 和 PHP 8.4 头文件(php8.4-dev)
# php8.4-embed 安装后 libphp.so 即位于 $PHP_HOME/lib(= /usr/lib),无需再手动拷贝
RUN set -eux \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        cmake \
        curl \
        libgmp-dev \
        libmpfr-dev \
    && git clone https://github.com/swoole/phpx.git /opt/phpx \
    && cmake -S /opt/phpx -B /opt/phpx/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTS=OFF \
        -Dphp_dir="$PHP_HOME" \
        -DENABLE_FACADE_API=OFF \
    && cmake --build /opt/phpx/build --parallel 4 --target phpx \
    && case "$(uname -m)" in \
            aarch64|arm64) TPC_TARGET="arm64" ;; \
            x86_64|amd64)  TPC_TARGET="x64" ;; \
            *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;; \
        esac \
    && TPC_URL="https://github.com/swoole/typephp/releases/download/${TYPEPHP_VERSION}/tpc_${TYPEPHP_VERSION}_linux_${TPC_TARGET}_php${PHP_VERSION}-zts.tar.gz" \
    && echo "Downloading tpc (${TPC_TARGET}): ${TPC_URL}" \
    && curl -fsSL -o tpc.tar.gz "${TPC_URL}" \
    && mkdir /root/typephp \
    && tar -xzf tpc.tar.gz -C /root/typephp \
    && mv /root/typephp/*/* /root/typephp \
    && rm -f tpc.tar.gz

WORKDIR /opt/www

COPY . .

