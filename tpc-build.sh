#!/usr/bin/env bash
#
# tpc-build.sh — TypePHP 打包当前 Hyperf 项目(AOT 编译),不改动任何源码。
#
# 关键设计(遵循"通过脚本临时处理,而非修改源码"):
#  - config/config.php 保持原样: 'scan_cacheable' => env('SCAN_CACHEABLE', false)
#  - 注解缓存生成的开关靠 docker 内注入环境变量 SCAN_CACHEABLE=true 完成:
#      1) 预热: php 解释器跑一次 bin/hyperf.php,实时扫描并写入 runtime/container 缓存
#      2) 编译: tpc project.yml(编译本身不读该配置)
#      3) 运行: 产物读缓存(不实时扫描 AOT 类),同样需 SCAN_CACHEABLE=true
#  - 不写 vendor、不写 config、不写 app;临时处理全部发生在脚本与 docker 环境变量内。
#
# 用法:
#   ./typephp-docker/tpc-build.sh            # 等价 tpc project.yml -O0
#   ./typephp-docker/tpc-build.sh -O2 -j 8   # 透传 tpc 参数
#
# 环境变量:
#   TYPEPHP_IMAGE      镜像名,默认 typephp:latest
#   TYPEPHP_NO_BUILD   1:镜像缺失时直接失败,不自动构建
#   AOT_OUTPUT         产物文件名,默认 hyperf-server-aot
#
# 依赖:本项目 project.yml、hyperf-aot/main.php、runtime/container(脚本自动预热生成)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE="${TYPEPHP_IMAGE:-typephp:latest}"
# 产物名默认取自 project.yml 的 name,并按 tpc 规则把 `-` 转 `_`(hyperf-server → hyperf_server);
# 可被 AOT_OUTPUT 覆盖(注意 tpc 仍会把传入名中的 `-` 转 `_`)。
TPC_NAME="$(grep -E '^name:' "${PROJECT_ROOT}/project.yml" | head -1 | awk -F': ' '{print $2}')"
OUTPUT="${AOT_OUTPUT:-${TPC_NAME//-/_}}"
DR="/opt/www"                             # 容器内工作目录(挂载项目根)
TCPC_ARGS=("${@:--O0}")                   # 默认 -O0;命令行参数原样透传

cd "${PROJECT_ROOT}"

# ---------- 0. docker / 镜像就绪 ----------
if ! command -v docker >/dev/null 2>&1; then
    echo "错误: 未找到 docker,请先安装或用 TYPEPHP_USE_LOCAL 走本机 tpc。" >&2
    exit 1
fi
if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
    if [[ "${TYPEPHP_NO_BUILD:-0}" == "1" ]]; then
        echo "错误: 镜像 ${IMAGE} 不存在(已禁用自动构建,见 TYPEPHP_NO_BUILD)。" >&2
        exit 1
    fi
    echo "[tpc-build] 镜像 ${IMAGE} 不存在,从 typephp-docker/ 构建..." >&2
    docker build -t "${IMAGE}" "${SCRIPT_DIR}"
fi

# ---------- 1. 预热注解扫描缓存(php 解释器 + SCAN_CACHEABLE=true) ----------
echo "[tpc-build] 1/3 预热注解缓存: 清空 runtime/container → php 解释器扫描并写缓存"
docker run --rm \
    -e SCAN_CACHEABLE=true \
    -v "${PROJECT_ROOT}:${DR}" -w "${DR}" \
    "${IMAGE}" \
    bash -c 'rm -rf runtime/container && php bin/hyperf.php >/dev/null 2>&1'
CACHE_LIST="$(ls runtime/container/*.cache 2>/dev/null | xargs -n1 basename | tr '\n' ' ' || true)"
if [[ -n "${CACHE_LIST}" ]]; then
    echo "          → 缓存已生成: ${CACHE_LIST}"
else
    echo "错误: 预热未产出 runtime/container/*.cache,后续编译请另查。" >&2
    exit 1
fi

# ---------- 2. tpc 编译 project.yml ----------
echo "[tpc-build] 2/3 编译 project.yml ${TCPC_ARGS[*]}"
docker run --rm \
    -v "${PROJECT_ROOT}:${DR}" -w "${DR}" \
    "${IMAGE}" \
    tpc project.yml "${TCPC_ARGS[@]}"

# ---------- 3. 确认产物 ----------
echo "[tpc-build] 3/3 完成"
if [[ -f "${PROJECT_ROOT}/${OUTPUT}" ]]; then
    ls -lh "${PROJECT_ROOT}/${OUTPUT}"
    echo "产物: ./${OUTPUT}"
else
    echo "注意: 未在项目根找到 ./${OUTPUT}(产物名可能不同,请查看上方构建日志)。" >&2
fi
cat <<EOF

运行 AOT 产物(同样需在 docker 内注入 SCAN_CACHEABLE=true,直接读缓存、不实时扫描 AOT 类):
  docker run -e SCAN_CACHEABLE=true -p 9501:9501 \\
    -v "\$PWD":/opt/www -w /opt/www \\
    -v "\$PWD/typephp-docker/99-typephp.ini":/usr/local/etc/php/conf.d/99-typephp.ini:ro \\
    "${IMAGE}" ./${OUTPUT} start

示例(产物 ${OUTPUT}):
  docker run -e SCAN_CACHEABLE=true -p 9501:9501 \\
    -v "\$PWD":/opt/www -w /opt/www \\
    -v "\$PWD/typephp-docker/99-typephp.ini":/usr/local/etc/php/conf.d/99-typephp.ini:ro \\
    "${IMAGE}" ./${OUTPUT} start
EOF