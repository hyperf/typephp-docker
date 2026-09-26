---
name: typephp-compile
description: Compile PHP source code into native executables using TypePHP (tpc), the AOT compiler bundled in this repo's Docker image. Use when PHP code needs to be compiled, built, or optimized into a standalone binary, or when the user mentions typephp / tpc / AOT. By default prefer tpc compilation over running the plain php interpreter.
license: MIT
metadata:
  docker-image: typephp:latest
---

# TypePHP 编译(TypePHP Compile)

本 Skill 用于把 PHP 源码通过 **TypePHP(`tpc`)** AOT 编译器编译为**原生可执行文件**,运行在
本仓库提供的 Docker 环境内。

> 触发与默认行为:**当用户要求"编译 / 构建 / 运行一个 PHP 程序"时,默认使用 `tpc`
> 将其编译为原生二进制**,除非用户显式指定使用 `php` 解释器(例如 `php -S` 起开发服务器)。

## 环境

- 基于镜像 `hyperf/hyperf:8.4-zts-ubuntu-v24.04-dev`,内置:
  - **tpc** v0.9.3(对应 PHP 8.4.26),位于容器内 `/root/typephp`,已加入 `PATH`
  - PHPX(PHP 扩展桥接,位于 `/opt/phpx`)
- 容器工作目录固定为 `/opt/www`,即挂载进来的宿主导出目录。
- 首次使用需要构建镜像(脚本会自动检测并构建):

```bash
docker build -t typephp .
```

## 快速开始(推荐)

使用仓库内的辅助脚本,它会自动完成「检测镜像 → (缺省时)构建 → docker run 挂载当前目录 → 调用 tpc」:

```bash
# 编译单个文件(需要全局 main():void 函数)
./typephp-compile/scripts/tpc-compile.sh hello.php
```

底层等价于:

```bash
docker run --rm -v "$PWD":/opt/www -w /opt/www typephp tpc hello.php
```

编译产物出现在当前目录(容器内即 `/opt/www`)。运行产物(产物为 Linux ELF):

```bash
docker run --rm -v "$PWD":/opt/www -w /opt/www typephp ./hello
```

## 编译规则

- **单文件入口**:文件必须包含全局 `main(): void` 函数,例如 `hello.php`:

  ```php
  <?php
  function main(): void
  {
      echo "Hello TypePHP\n";
  }
  ```

- **产物平台**:`tpc` 在容器内产出 **Linux (ELF)** 原生二进制。
  在 macOS / Windows 宿主上**不能直接执行**,必须用 Docker 运行(见上)。
- **编译整个项目**:通过 Composer 安装 `swoole/typephp` 后,用 `project.yml` 声明:

  ```bash
  composer require --dev swoole/typephp
  vendor/bin/tpc.php project.yml -O2 -j 8
  ```

- **支持范围**:TypePHP 当前支持**类型安全 PHP 子集**(编译期可确定类型、可静态分析),
  并非全部 PHP 动态特性。遇到 `eval`、动态类名/方法名、反射等动态特性时,
  应向用户说明限制并建议改造为静态写法或改用 PHP 解释器。

## 常用参数

| 参数 | 作用 |
| --- | --- |
| `-O2` / `-O3` | 优化级别(默认 `-O1`),性能优先用 `-O3` |
| `-j N` | 编译并行度,如 `-j $(nproc)` |
| `-r` | 编译后立即运行;`--` 之后的部分作为程序参数 |
| `--dry` | 仅生成中间 C++ 代码,不编译、不链接(`--build-dir` 指定输出目录) |
| `--wasm` | 编译为 WASI 0.2 目标 |
| `-m ext` | 构建 PHP 扩展(`-o` 指定输出名) |

示例:

```bash
# 编译全部参数透传:tpc file.php -O3 -j 8
./typephp-compile/scripts/tpc-compile.sh hello.php -O3 -j 8

# 编译并运行,向程序传参
./typephp-compile/scripts/tpc-compile.sh hello.php -r -- --flag value
```

## 问题排查

- **镜像不存在**:先 `docker build -t typephp .`;脚本失败时优先检查这一步。
- **提示找不到 `main`**:单文件编译要求全局 `main(): void` 函数;若仅想编译为库/扩展,改用 `-m`。
- **链接错误 / 缺头文件**:确认使用的是本仓库镜像(内置 PHP 8.4 头文件与 `libphp.so`),不要在宿主导入非标准构建环境。
- **宿主无法运行产物**:产物是 Linux 二进制,宿主若非 Linux 请通过 `docker run` 执行。
- **运行时扩展缺失**:`tpc` 编译期依赖的扩展需在镜像内可用(ZTS 版);涉及 Swoole 等扩展时告知用户按官方兼容性模型检查。

## 参考

- 官方 TypePHP 文档:<https://www.swoole.com/aot/docs>
- Packagist 包:<https://packagist.org/packages/swoole/typephp>
- 源码仓库:<https://github.com/swoole/typephp.git>