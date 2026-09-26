#!/usr/bin/env bash
#
# tpc-build.sh — TypePHP 打包当前 Hyperf 项目(AOT 编译),不改动任何源码。
#
# 本脚本属于 typephp-compile SKILL(自包含):编译环境(assets/Dockerfile)、配套工具
# (assets/proxy-exclude.php / build-aot-config.php)、项目脚手架模板(templates/) 全部内嵌在
# SKILL 内——仓库根即 SKILL 根,git clone 到项目 .claude/skills/typephp-compile 即可使用。
# 项目根取「调用时所在目录」
# ($PWD),或以环境变量 TPC_PROJECT_ROOT 显式指定。
#
# 关键设计(遵循"通过脚本临时处理,而非修改源码"):
#  - config/config.php 保持原样: 'scan_cacheable' => env('SCAN_CACHEABLE', false)
#  - 注解缓存生成的开关靠 docker 内注入环境变量 SCAN_CACHEABLE=true 完成:
#      1) 预热: php 解释器跑一次 bin/hyperf.php,实时扫描并写入 runtime/container 缓存,并生成代理类
#      2) 代理类反推: 解析 runtime/container/proxy/*.proxy.php → 反推"运行时被同名代理类替换、
#         不可进 AOT"的源码文件,由 build-aot-config.php 注入到临时配置的 ignore(在容器内执行,
#         不依赖宿主 php;不对 project.yml、app、vendor 做任何改动)
#      3) 编译: tpc aot-project.yml(自动生成的临时配置,必须放项目根——tpc 以配置目录解析相对路径)
#      4) 运行: 产物读缓存(不实时扫描 AOT 类),同样需 SCAN_CACHEABLE=true
#  - 首次运行若项目缺 project.yml / hyperf-aot/main.php,会从 SKILL templates/ 自动生成(见步骤 0.5)
#  - 不写 vendor、不写 config、不写 app;临时处理全部发生在脚本与 docker 环境变量内。
#
# 用法(在项目根执行):
#   <skill>/scripts/tpc-build.sh            # 等价 tpc aot-project.yml -O0
#   <skill>/scripts/tpc-build.sh -O2 -j 8   # 透传 tpc 参数
#
# 环境变量:
#   TYPEPHP_IMAGE      镜像名,默认 typephp:latest
#   TYPEPHP_NO_BUILD   1:镜像缺失时直接失败,不自动构建
#   AOT_OUTPUT         产物文件名,默认取 project.yml 的 name(连字符转下划线)
#   TPC_PROJECT_ROOT   项目根,默认 $PWD(脚本会内部 cd 过去)
#   TPC_BOOT           预热启动命令,默认 "php bin/hyperf.php"
#
# 依赖:项目 bin/hyperf.php、vendor/autoload.php、config/container.php;可选 project.yml、
#       hyperf-aot/main.php(缺省自动从模板生成)。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"            # SKILL 根 = 脚本所在目录的上级
PROJECT_ROOT="${TPC_PROJECT_ROOT:-$PWD}"              # 项目根,默认调用时所在目录
IMAGE="${TYPEPHP_IMAGE:-typephp:latest}"

# 产物名默认取自 project.yml 的 name,并按 tpc 规则把 `-` 转 `_`(hyperf-server → hyperf_server);
# 可被 AOT_OUTPUT 覆盖(注意 tpc 仍会把传入名中的 `-` 转 `_`)。
# 注意: project.yml 的 name 行必须为纯键值(禁止行内注释),否则会被注释文本污染。
TPC_NAME="$(grep -E '^name:' "${PROJECT_ROOT}/project.yml" | head -1 | awk -F': ' '{print $2}')"
OUTPUT="${AOT_OUTPUT:-${TPC_NAME//-/_}}"
DR="/opt/www"                             # 容器内工作目录(挂载项目根)
TCPC_ARGS=("${@:--O0}")                   # 默认 -O0;命令行参数原样透传
TPC_BOOT="${TPC_BOOT:-php bin/hyperf.php}"

cd "${PROJECT_ROOT}"

# ---------- 0. docker / 镜像就绪 ----------
if ! command -v docker >/dev/null 2>&1; then
    echo "错误: 未找到 docker,请先安装。" >&2
    exit 1
fi
if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
    if [[ "${TYPEPHP_NO_BUILD:-0}" == "1" ]]; then
        echo "错误: 镜像 ${IMAGE} 不存在(已禁用自动构建,见 TYPEPHP_NO_BUILD)。" >&2
        exit 1
    fi
    echo "[tpc-build] 镜像 ${IMAGE} 不存在,从 SKILL assets/ 构建..." >&2
    docker build -t "${IMAGE}" "${SKILL_DIR}/assets"
fi

# ---------- 0.5 项目预检 + 模板自动生成(首次使用开箱即用) ----------
missing=0
for f in bin/hyperf.php vendor/autoload.php config/container.php; do
    if [[ ! -f "${PROJECT_ROOT}/${f}" ]]; then
        echo "错误: 缺少 ${PROJECT_ROOT}/${f} —— 看起来不是可打包的 Hyperf 项目。" >&2
        missing=1
    fi
done
[[ "${missing}" == "1" ]] && exit 1

if [[ ! -f "${PROJECT_ROOT}/project.yml" ]]; then
    cp "${SKILL_DIR}/templates/project.yml" "${PROJECT_ROOT}/project.yml"
    echo "[tpc-build] 未发现 project.yml,已从模板生成 ${PROJECT_ROOT}/project.yml"
    echo "           → 请查看 name(产物名)与 sources(需 AOT 的目录),按需调整后重跑。"
fi
if [[ ! -f "${PROJECT_ROOT}/hyperf-aot/main.php" ]]; then
    mkdir -p "${PROJECT_ROOT}/hyperf-aot"
    cp "${SKILL_DIR}/templates/hyperf-aot/main.php" "${PROJECT_ROOT}/hyperf-aot/main.php"
    echo "[tpc-build] 已从模板生成 ${PROJECT_ROOT}/hyperf-aot/main.php(项目入口结构不同请自行调整)。"
fi

# 对已有 project.yml 做轻量校验(不中断,仅告警)
NAME_VAL="$(grep -E '^name:' "${PROJECT_ROOT}/project.yml" | head -1 | awk -F': ' '{print $2}')"
if [[ -z "${NAME_VAL}" ]]; then
    echo "警告: project.yml 无有效的 name: 行(产物名将为空)。name 行须为纯键值,禁止行内注释。" >&2
fi
if ! grep -qE '^sources:' "${PROJECT_ROOT}/project.yml"; then
    echo "警告: project.yml 缺少 sources: 块,将无源码入 AOT 域。参考 SKILL templates/project.yml。" >&2
fi

# ---------- 1. 预热注解扫描缓存(php 解释器 + SCAN_CACHEABLE=true) ----------
# 预热会实时扫描注解并写入 runtime/container 缓存,同时为带 #[Inject] 等注解的类生成
# 同名代理类到 runtime/container/proxy/ —— 代理类正是判断"哪些源码文件不该进 AOT"的依据。
echo "[tpc-build] 1/4 预热注解缓存: 清空 runtime/container → php 解释器扫描并写缓存 + 生成代理类"
docker run --rm \
    -e SCAN_CACHEABLE=true \
    -v "${PROJECT_ROOT}:${DR}" -w "${DR}" \
    "${IMAGE}" \
    bash -c "rm -rf runtime/container && ${TPC_BOOT} >/dev/null 2>&1"
CACHE_LIST="$(ls runtime/container/*.cache 2>/dev/null | xargs -n1 basename | tr '\n' ' ' || true)"
if [[ -n "${CACHE_LIST}" ]]; then
    echo "          → 缓存已生成: ${CACHE_LIST}"
    echo "          → 代理类: $(ls runtime/container/proxy/*.proxy.php 2>/dev/null | xargs -n1 basename | tr '\n' ' ' || echo 无)"
else
    echo "错误: 预热未产出 runtime/container/*.cache,后续编译请另查。" >&2
    exit 1
fi

# ---------- 2. 代理类反推:排除"运行时被同名代理类替换、不可进 AOT"的源码文件 ----------
# 在容器内执行(镜像自带 php≥8.0,不依赖宿主 php):
#   proxy-exclude.php     读取 runtime/container/proxy 反推 FQCN → psr-4 相对路径
#   build-aot-config.php  将反推结果注入 project.yml 的 ignore,生成项目根 aot-project.yml
# assets 目录以只读方式装配到容器 /opt/skill(build-aot-config 内部 shell_exec 会按 __DIR__
# 再调一次 proxy-exclude.php,两文件必须同目录)。
echo "[tpc-build] 2/4 代理类反推: 解析 runtime/container/proxy → 生成 aot-project.yml"
AOT_CONFIG_REL="aot-project.yml"
docker run --rm \
    -v "${PROJECT_ROOT}:${DR}" -w "${DR}" \
    -v "${SKILL_DIR}/assets:/opt/skill:ro" \
    "${IMAGE}" \
    bash -c 'php /opt/skill/proxy-exclude.php /opt/www > runtime/.proxy-excluded.list 2>/dev/null || true
php /opt/skill/build-aot-config.php /opt/www /opt/www/aot-project.yml'
if [[ -s "${PROJECT_ROOT}/runtime/.proxy-excluded.list" ]]; then
    echo "          → 反推出的排除文件(这些源码运行时被代理类替换,不进 AOT):"
    sed 's/^/             - /' "${PROJECT_ROOT}/runtime/.proxy-excluded.list"
else
    echo "          → 本配置无代理类,无额外排除。"
fi

# ---------- 3. tpc 编译(用临时配置) ----------
echo "[tpc-build] 3/4 编译 ${AOT_CONFIG_REL} ${TCPC_ARGS[*]}"
docker run --rm \
    -v "${PROJECT_ROOT}:${DR}" -w "${DR}" \
    "${IMAGE}" \
    tpc "${AOT_CONFIG_REL}" "${TCPC_ARGS[@]}"

# ---------- 4. 确认产物 ----------
echo "[tpc-build] 4/4 完成"
if [[ -f "${PROJECT_ROOT}/${OUTPUT}" ]]; then
    ls -lh "${PROJECT_ROOT}/${OUTPUT}"
    echo "产物: ./${OUTPUT}"
else
    echo "注意: 未在项目根找到 ./${OUTPUT}(产物名可能不同,请查看上方构建日志)。" >&2
fi
cat <<EOF

运行 AOT 产物(推荐直接用本 SKILL 的 scripts/run-aot.sh):
  ${SKILL_DIR}/scripts/run-aot.sh

等价 docker 命令(99-typephp.ini 由 SKILL assets/ 提供,需注入 SCAN_CACHEABLE=true 直接读缓存):
  docker run -e SCAN_CACHEABLE=true -p 9501:9501 \\
    -v "\$PWD":/opt/www -w /opt/www \\
    -v "${SKILL_DIR}/assets/99-typephp.ini":/usr/local/etc/php/conf.d/99-typephp.ini:ro \\
    "${IMAGE}" ./${OUTPUT} start

示例(产物 ${OUTPUT}):
  ${SKILL_DIR}/scripts/run-aot.sh
EOF