#!/usr/bin/env bash
#
# run-aot.sh — 在 docker 内运行 TypePHP AOT 产物(Linux ELF)。
#
# 属于 typephp-compile SKILL(自包含):swoole.use_shortname=Off 配置(assets/99-typephp.ini)
# 由脚本自动挂载,无需项目内另存一份。注入 SCAN_CACHEABLE=true:直接读预热生成的注解缓存,
# 不实时扫描 AOT 类(避免 TypeError)。宿主 macOS 不能直接跑 ELF,一律经 docker。
#
# 用法(在项目根执行):
#   <skill>/scripts/run-aot.sh                # 默认端口 9501
#   AOT_PORT=9502 <skill>/scripts/run-aot.sh  # 自定义端口
#
# 环境变量:
#   TYPEPHP_IMAGE  镜像名,默认 typephp:latest
#   AOT_OUTPUT     产物文件名,默认 hyperf_server
#   AOT_PORT       对外端口,默认 9501

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"     # SKILL 根 = 脚本所在目录的上级
IMAGE="${TYPEPHP_IMAGE:-typephp:latest}"
OUTPUT="${AOT_OUTPUT:-hyperf_server}"
PORT="${AOT_PORT:-9501}"

if [[ ! -f "${OUTPUT}" ]]; then
    echo "错误: 未找到 ./${OUTPUT},请先在项目根执行本 SKILL 的 scripts/tpc-build.sh 编译产物。" >&2
    exit 1
fi

echo "[run-aot] 运行 ./${OUTPUT} start (端口 ${PORT},SCAN_CACHEABLE=true)"
docker run --rm -e SCAN_CACHEABLE=true -p "${PORT}:${PORT}" \
    -v "$PWD":/opt/www -w /opt/www \
    -v "${SKILL_DIR}/assets/99-typephp.ini":/usr/local/etc/php/conf.d/99-typephp.ini:ro \
    "${IMAGE}" ./"${OUTPUT}" start