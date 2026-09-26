---
name: typephp-compile
description: Compile PHP source code into native executables using TypePHP (tpc), the AOT compiler bundled in this repo's Docker image. Use when PHP code needs to be compiled, built, or optimized into a standalone binary, when the user mentions typephp / tpc / AOT, or when they want to AOT-compile a full framework project (e.g. Hyperf) into a native binary. By default prefer tpc compilation over running the plain php interpreter.
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

## 编译完整框架项目(Hyperf 等)

用 `tpc bin/hyperf.php` **直接编译 Hyperf 3.x 无法一步到位**,但**技术路线是通的**:动态特性
走 ZendVM fallback 解释、静态热点走 AOT 编译,二者混跑(Webman 的 `tinywan/webman-typephp`
插件已按同构思路验证)。不要把"编译失败"当成路走不通,按下面的约束改造即可。

### 已知硬限制(实测 Hyperf 3.2 + tpc v0.9.3)

1. **不支持 shebang / 入口 InlineHTML**:`#!/usr/bin/env php` 会被解析为 `Stmt_InlineHTML`,直接报错。编译前去掉 shebang。
2. **顶层可执行语句被禁止**:二进制模式全局作用域**只允许声明**。`ClassLoader::init()`、
   `define(...)`、`$container->get(...)` 等执行代码必须放进函数,否则报
   `All execution code must be within a function, found stray code`。
3. **必须有全局 `main(): void`**:二进制模式强制 `function main(): void`(可带
   `main(int $argc, array $argv)`),返回值须为 void。

改造入口即可绕过:把 `bin/hyperf.php` 的顶层逻辑搬进 `main()`,常量用
`defined('X') || define('X', ...)` 守护。

### 动态特性走 ZendVM fallback(能跑、不 AOT 加速)

注解(`#[Constants]` / `#[Message]` / `#[Listener]`)、DI 容器注入、`__call` 动态派发、
协程上下文(`Hyperf\Context\Context`)、`di()` 全局函数、反射、动态类名……这些**不会让 tpc
拒绝编译**,而是运行时回落 ZendVM 解释执行。**不要追求全量 AOT**,静态热点被编译即有收益。

### 多文件项目能力(project.yml 常用项)

- `sources`:构建源(目录 / 条件 `if:`);`ignore`、`optimize`、`php-version`、`build-dir`、`sapi`。
- `embedded-files: [vendor]`:把 vendor 转字节码嵌入二进制,运行时 require 走内存,
  产物流转时**无需 Composer 与磁盘 vendor**(与 Composer autoload 一起嵌入)。
- `php-builder`:从 php-src 构建**私有 PHP 运行时**,可显式 `extensions: [swoole, mongodb]` +
  `zts: on`——Hyperf 获得 Swoole 运行时的一条官方路径。
- `ext-deps: [swoole, redis, pdo_mysql, pcntl, openssl, ...]`:声明运行时扩展依赖,
  通过 php.ini 加载宿主 `libphp` 的扩展 .so(另一条路径)。
- **不兼容特性(与 Hyperf 强相关)**:`$$`、`extract()` 不支持;`yield`/generator 用 Fiber 替;
  `Closure::bind() / bindTo() / call()` 不支持;`declare(ticks)` 不支持;
  强类型(`strict_types=1`)恒为 on。完整清单见 TypePHP 源码
  `docs/zh-cn/INCOMPATIBLE_PHP_FEATURES.md`。

### 分阶段编译路线(每步有明确验证信号,避免一次投入撞硬墙)

1. **M1 单文件环路**:写含 `main(): void` 的 hello 编译并在 docker 内运行 → 验证镜像/挂载/产物链条。
2. **M2 最小 Swoole HTTP 服务器**:容器内补装 `swoole.so`(phpize 源码编译,ZTS),php.ini 加载;
   写 `main(){ $http = new Swoole\Coroutine\Http\Server('0.0.0.0', 9501); ... }`,宿主
   `curl localhost:9501` 通。**Swoole 扩展在 TypePHP 产物内可用是全方案最大风险点,必须最先验证**。
3. **M3 Hyperf AOT 入口**:新建 `hyperf-aot/main.php`,在 `main()` 内
   `require vendor/autoload → ClassLoader::init() → 构建容器 → get(ApplicationInterface) → run()`;
   project.yml `sources` 先 `[hyperf-aot, app]` 再从纯 app 逐步扩到必要 vendor,一路修编译错。
4. **M4 完整 smoke test**:产物收束便携目录(见下),docker 内连 MySQL/Redis、命中 controller。
5. **M5 产物化**:把 M1–M4 命令固化为构建脚本 / Makefile,支持 `TYPEPHP_IMAGE` / `TYPEPHP_USE_LOCAL`。

### 产物形态与部署

便携目录 = ELF + `libphp.so` + `libphpx.so` + `php.ini` + `ext/*.so` + `lib/`(ldd 收集),
运行时需 `LD_LIBRARY_PATH` 含 phpx/libphp。非 Linux 宿主须在 docker 内跑 smoke test。

### 风险与缓解

| 风险 | 等级 | 缓解 / 回退 |
|---|---|---|
| Swoole 扩展在产物内不可用(ZTS ABI / 事件循环 / Embed SAPI 主循环冲突) | **高** | M2 前置验证;失败走 `php-builder` 私有运行时;再失败用 `-m ext` 把热点业务编译为扩展挂到原生 Hyperf |
| 注解/容器/代理动态面导致大量编译错(ProxyManager 动态生成类、AnnotationCollector 反射) | **高** | `SCAN_CACHEABLE=true` 预生成代理类;动态代码靠 ZendVM fallback;把 `app/` 抽特定类加入 sources 逐个验证 |
| 扩展在 aarch64 + PHP 8.4 ZTS 需重新编译 | 中 | 容器内 phpize + make(镜像已有 gcc) |
| 产物体积 / 部署复杂度 | 低 | 便携目录方案已业界验证 |

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
- **Hyperf / 框架项目直接编译报 shebang / stray code / 缺 main**:去掉 shebang,把顶层执行代码搬进全局 `main(): void`,常量用 `defined() || define(...)` 守护;动态特性会走 fallback,不要追求全量 AOT。
- **Swoole 扩展缺失或产物内不可用**:先做 M2 最小 Swoole server 验证;不行换 `php-builder` 私有运行时,或 `ext-deps` 声明运行时扩展。

## 参考

- 官方 TypePHP 文档:<https://www.swoole.com/aot/docs>
- Packagist 包:<https://packagist.org/packages/swoole/typephp>
- 源码仓库:<https://github.com/swoole/typephp.git>
- TypePHP 不兼容特性清单(源码 `docs/zh-cn/INCOMPATIBLE_PHP_FEATURES.md`)
- Webman 二进制构建插件 <https://github.com/tinywan/webman-typephp>(同构框架编译先例)