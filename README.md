# typephp-compile(TypePHP 编译 Skill)

本仓库即一个开箱即用的 [Agent Skills](https://github.com/anthropics/agent-skills) 编译 **Skill**:
把 PHP 源码通过 **TypePHP(`tpc`)** AOT 编译器编译为**原生可执行文件**。

**仓库根目录即 SKILL 根**,编译环境(`assets/Dockerfile`)、辅助脚本(`scripts/`)、项目脚手架
模板(`templates/`)与冒烟样例(`fixtures/`)全部内嵌其中,**自包含,不依赖项目内任何文件**。

- 基础镜像:`hyperf/hyperf:8.4-zts-ubuntu-v24.04-dev`(内置 PHP 8.4 头文件与 `libphp.so`)
- 内置 `tpc` v0.9.3(对应 PHP 8.4.26),位于容器内 `/root/typephp`,已加入 `PATH`
- 容器工作目录固定 `/opt/www`,与宿主导入的当前目录挂载对应

## 安装(推荐 git clone)

在**需要编译 PHP 的项目**中执行:

```bash
cd <你的项目>
mkdir -p .claude/skills
git clone https://github.com/hyperf/typephp-docker.git .claude/skills/typephp-compile
```

之后 Claude Code(或其他支持 Agent Skills 的工具)会自动识别 `.claude/skills/typephp-compile/SKILL.md`;
用户提到"编译 / 构建 PHP 程序"时,默认优先使用 `tpc` 而非 `php` 解释器。

## 快速使用

```bash
# 单文件编译(自动检测镜像 → 缺省构建 → docker 挂载当前目录 → 调用 tpc)
.claude/skills/typephp-compile/scripts/tpc-compile.sh hello.php

# 等价底层命令
docker run --rm -v "$PWD":/opt/www -w /opt/www typephp tpc hello.php
```

`fixtures/hello.php` 为可编译冒烟样例,包含 `tpc` 所需的全局 `main(): void` 函数;编译产物
为 Linux ELF,出现在当前目录,非 Linux 宿主须经 docker 运行:

```bash
docker run --rm -v "$PWD":/opt/www -w /opt/www typephp ./hello
# Hello TypePHP
```

编译 Hyperf 等完整框架项目,推荐 `<skill>/scripts/tpc-build.sh`(四步打包:预热注解缓存 →
代理类反推 → AOT 编译 → 确认产物),细节见 `SKILL.md`。

## 目录结构

```
<skill>/                           # ← 本仓库根,克隆到 .claude/skills/typephp-compile 后即该目录
├── SKILL.md                       # Skill 定义与完整使用指南(含已知硬限制 / 排查 / AOT 边界)
├── scripts/
│   ├── tpc-compile.sh             # 单文件 / 简单项目编译
│   ├── tpc-build.sh               # Hyperf 等框架项目「四步打包」(推荐入口)
│   └── run-aot.sh                 # 运行 AOT 产物(Linux ELF,经 docker)
├── assets/
│   ├── Dockerfile                 # tpc 编译环境镜像(php 8.4 zts + swoole + tpc)
│   ├── 99-typephp.ini             # swoole.use_shortname=Off(运行 AOT 产物时挂载)
│   ├── proxy-exclude.php          # 代理类反推(排除 #[Inject] 同名代理类对应源码)
│   └── build-aot-config.php       # 生成临时编译配置 aot-project.yml
├── templates/
│   ├── project.yml                # 通用编译配置骨架
│   └── hyperf-aot/main.php        # Hyperf AOT 入口模板(泛化,无项目硬编码)
└── fixtures/
    ├── hello.php                  # 单文件冒烟验证样例
    └── swoole-server.php          # 最小 Swoole HTTP 服务器(M2 演示样例)
```

## 手动构建镜像

脚本在镜像缺失时会自动用 `<skill>/assets/` 构建;也可手工构建:

```bash
docker build -t typephp:latest <skill>/assets
```

## 参考

- TypePHP 官方文档:<https://www.swoole.com/aot/docs>
- Packagist:<https://packagist.org/packages/swoole/typephp>
- 源码:<https://github.com/swoole/typephp.git>
- PHPX:<https://github.com/swoole/phpx.git>