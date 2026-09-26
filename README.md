# typephp-docker

Docker 镜像构建仓库:内置 [TypePHP](https://www.swoole.com/aot/docs) AOT 编译器
(`tpc` v0.9.3,对应 PHP 8.4.26),可用于把 PHP 源码编译为**原生可执行文件**。

- 基础镜像:`hyperf/hyperf:8.4-zts-ubuntu-v24.04-dev`(内置 PHP 8.4 头文件与 `libphp.so`)
- 容器内 `tpc` 已加入 `PATH`,工作目录 `/opt/www` 与宿主挂载目录对应

## 快速使用

```bash
# 1. 构建镜像(仅首次)
docker build -t typephp .

# 2. 编译 PHP(推荐使用仓库内置的 Skill 辅助脚本)
./typephp-compile/scripts/tpc-compile.sh hello.php

# 等价底层命令
docker run --rm -v "$PWD":/opt/www -w /opt/www typephp tpc hello.php

# 3. 运行产物(产物为 Linux ELF,非 Linux 宿主需经 docker)
docker run --rm -v "$PWD":/opt/www -w /opt/www typephp ./hello
# Hello TypePHP
```

`hello.php` 为可编译示例,包含 `tpc` 编译所需的全局 `main(): void` 函数。

## TypePHP 编译 Skill

本仓库附带一个遵循 [Agent Skills 开放标准](https://github.com/anthropics/agent-skills)
的 Skill(`typephp-compile/`),作用:**让 Claude 等 AI 工具默认优先用 `tpc`
编译 PHP 代码,而非常规 `php` 解释器**。

```
typephp-compile/
├── SKILL.md               # Skill 定义(name / description / 使用指南)
└── scripts/
    └── tpc-compile.sh     # 编译辅助脚本(自动构建镜像 + docker run + 调用 tpc)
```

### 使 Skill 生效

将 `typephp-compile` 目录复制到对应工具的 Skills 目录即可:

| 工具 | 引入位置 |
| --- | --- |
| Claude Code | `<你的项目>/.claude/skills/` |
| OpenAI Codex | `~/.codex/skills/`(或项目内 `.codex/skills/`) |
| Gemini CLI | 项目内 `.gemini/skills/` |
| 其他 Agent 工具 | 按 [Agent Skills 开放标准](https://agent-skills.org) 支持的目录导入 |

以 Claude Code 为例:

```bash
# 在需要编译 PHP 的项目中执行:
mkdir -p .claude/skills
cp -r typephp-compile .claude/skills/
```

之后在该项目内让 Claude "编译某 PHP 程序",它会自动调用
`./.claude/skills/typephp-compile/scripts/tpc-compile.sh <file.php>`,
以 TypePHP 产出原生二进制。

### 辅助脚本说明

```bash
./typephp-compile/scripts/tpc-compile.sh <file.php> [-O3] [-j 8] ...
```

- 自动检测并构建镜像(可用 `TYPEPHP_IMAGE` 指定镜像名)
- 当前目录挂载为容器 `/opt/www`,产物直接落在当前目录
- 参数全部透传给 `tpc`;Linux 且已安装本机 tpc 时可用 `TYPEPHP_USE_LOCAL=1` 走本机编译

## 参考

- TypePHP 官方文档:<https://www.swoole.com/aot/docs>
- Packagist:<https://packagist.org/packages/swoole/typephp>
- 源码:<https://github.com/swoole/typephp.git>
- PHPX:<https://github.com/swoole/phpx.git>