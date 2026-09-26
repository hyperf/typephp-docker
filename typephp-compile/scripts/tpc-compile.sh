#!/usr/bin/env bash
#
# tpc-compile.sh — 使用 TypePHP(tpc) 将 PHP 源码编译为原生可执行文件。
#
# 本脚本属于 typephp-compile SKILL(自包含):编译环境(Dockerfile 等)位于 SKILL 的
# assets/ 目录 —— 把整个 typephp-compile/ 目录复制到任意项目 .claude/skills/ 下即开箱可用,
# 不依赖仓库根或项目内任何文件。
#
# 默认在 Docker 容器内执行编译:
#   docker run --rm -v "$PWD":/opt/www -w /opt/www <image> tpc <args...>
# 若在 Linux 宿主且已安装本机 tpc,并设置 TYPEPHP_USE_LOCAL=1,则直接调用本机 tpc。
#
# 用法(在待编译文件所在目录执行):
#   ./tpc-compile.sh <file.php> [tpc 参数...]
#   ./tpc-compile.sh app.php -O3 -j 8
#   ./tpc-compile.sh hello.php -r -- --flag value
#
# 环境变量:
#   TYPEPHP_IMAGE      镜像名,默认 typephp:latest
#   TYPEPHP_USE_LOCAL  设为 1 时优先使用本机 tpc(需已安装)
#   TYPEPHP_NO_BUILD   设为 1 时,镜像缺失不自动构建,直接失败

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"   # SKILL 根 = 脚本所在目录的上级
IMAGE="${TYPEPHP_IMAGE:-typephp:latest}"

usage() {
    cat >&2 <<'EOF'
用法: tpc-compile.sh <file.php|project.yml> [tpc 参数...]

在 Docker 镜像(TypePHP 编译环境)内调用 tpc 编译 PHP 源码为原生二进制。

示例:
  ./tpc-compile.sh hello.php            # 编译单文件,产物 ./hello
  ./tpc-compile.sh app.php -O3 -j 8     # 带优化与并行
  ./tpc-compile.sh hello.php -r -- --flag value

环境变量:
  TYPEPHP_IMAGE      镜像名(默认 typephp:latest)
  TYPEPHP_USE_LOCAL=1 使用本机 tpc(无需 Docker)
EOF
}

# 0 个参数仍需参数;这里用 $# 判断是否完全无参
if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

# 模式一:使用本机 tpc(显式要求 && 确实存在)
if [[ "${TYPEPHP_USE_LOCAL:-0}" == "1" ]]; then
    if command -v tpc >/dev/null 2>&1; then
        exec tpc "$@"
    fi
    echo "tpc-compile: TYPEPHP_USE_LOCAL=1 但当前环境未找到本机 tpc" >&2
    exit 1
fi

# 模式二(默认):Docker 内编译
if ! command -v docker >/dev/null 2>&1; then
    echo "tpc-compile: 未找到 docker,请安装 Docker 或设置 TYPEPHP_USE_LOCAL=1(需本机 tpc)" >&2
    exit 1
fi

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
    if [[ "${TYPEPHP_NO_BUILD:-0}" == "1" ]]; then
        echo "tpc-compile: 镜像 ${IMAGE} 不存在(已禁用自动构建,见 TYPEPHP_NO_BUILD)" >&2
        exit 1
    fi
    echo "tpc-compile: 镜像 ${IMAGE} 不存在,正在用 SKILL assets/ 构建..." >&2
    docker build -t "${IMAGE}" "${SKILL_DIR}/assets"
fi

# 将调用者当前目录挂载为容器 /opt/www,保证相对路径与产物位置一致
exec docker run --rm \
    -v "$(pwd):/opt/www" \
    -w /opt/www \
    "${IMAGE}" tpc "$@"