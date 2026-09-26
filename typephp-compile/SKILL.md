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

> **经验维护约定**:TypePHP 编译经验(硬限制、踩坑、已验证方案)**统一持续维护到本文件**——
> 通用规则沉淀进正文各小节;按里程碑推进的具体项目实例记录见「分阶段编译路线」。

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
4. **AOT 类是"无源码类"**:AOT 编译的类经反射表现为内置类(`ReflectionClass::getFileName()`
   返回 `false`)。若框架对扫描到的类直接取文件名做 `filemtime`/`lastModified` 会触发
   `TypeError`。**规避:不改源码/vendor,运行时注入 `SCAN_CACHEABLE=true` 走注解缓存、
   不做实时扫描**(见「注解扫描适配」)。
5. **Swoole 5+ 协程要求**:`Swoole\Coroutine\Http\Server()->start()` **只能在协程上下文调用**
   (报 `Swoole\Error: API must be called in the coroutine`)。用
   `\Swoole\Coroutine\run(function () { ... $http->start(); })` 包裹服务器生命周期。
6. **Swoole.use_shortname=Off**:运行含 `go()`/`co()` 短函数的框架(如 Hyperf)时,Swoole
   要求 `swoole.use_shortname=Off`,否则启动报 `Swoole short function names must be disabled`。
   在容器 php.ini conf.d 追加该配置即可(产物运行时读取系统 php.ini 与 conf.d)。

改造入口即可绕过:把 `bin/hyperf.php` 的顶层逻辑搬进 `main()`,常量用
`defined('X') || define('X', ...)` 守护。

### 动态特性走 ZendVM fallback(能跑、不 AOT 加速)

注解(`#[Constants]` / `#[Message]` / `#[Listener]`)、DI 容器注入、`__call` 动态派发、
协程上下文(`Hyperf\Context\Context`)、`di()` 全局函数、反射、动态类名……这些**不会让 tpc
拒绝编译**,而是运行时回落 ZendVM 解释执行。**不要追求全量 AOT**,静态热点被编译即有收益。

### 业务代码静态编译边界(实测判定)

TypePHP 的 `prepare()` 会按"类继承/依赖关系"对源文件做**拓扑排序构建符号表**;凡
`extends` / `implements` 未列入 `sources` 的父类/接口,编译报
`inherits from a non-existent class`。据此判定业务类能否进 AOT:

| 业务类形态 | 能否 AOT | 说明 |
|---|---|---|
| `extends` / `implements` 框架基类(Listener、ExceptionHandler、Processor、Model 等) | ❌ | 需父类/接口也进编译域,会拉入整个框架依赖树,不可持续。改为走 ZendVM fallback |
| 依赖**注解收集**的类(如枚举 + `#[Message]`/`#[Constants]`) | ✅(配合 scan_cacheable) | 编译能过;注解元数据从预热的 `runtime/container` 缓存装载,不依赖实时扫描。前提:`SCAN_CACHEABLE=true` 运行(见「注解扫描适配」) |
| 带 `#[Inject]`(属性注解注入)的类,如 Controller 注入 Service | ❌ | 预热阶段会生成**同名代理类**(`runtime/container/proxy/<FQCN 下划线化>.proxy.php`,如 `App_Controller_IndexController.proxy.php`),运行时容器实例化的是代理类(同名替换)。源码文件若进 AOT,会与运行时代理类重声明冲突 Fatal `Cannot redeclare class`。由 tpc-build.sh「代理类反推」自动排除(见下节),无需手工维护 |
| 纯叶子类(不继承框架、无框架注解、无 `#[Inject]`,如控制器基类构造器注入) | ✅ | 可安全 AOT,走原生层加速。注意判定标准是「不含 `#[Inject]`」——带 `#[Inject]` 的一律归上一行 |

> 经验:Hyperf/类似框架按「**入口 + 纯业务热点 AOT,框架绑定业务走 ZendVM fallback**」
> 的**混合模式**推进,M3 已按此验证完整可用(产物运行 + 命中 controller)。

#### 代理类反推:自动排除被同名代理类替换的源码(不改 sources 清单)

**前置逻辑**:编译前**必须先用 php 解释器预热**(`php bin/hyperf.php`,注入 `SCAN_CACHEABLE=true`)。
预热会实时扫描注解写入 `runtime/container/*.cache`,同时为带 `#[Inject]` 等需代理的类生成
**同名代理类**(内容:`namespace App\Controller; class IndexController extends Controller { ... }`,
与原始类同名同 FQCN)到 `runtime/container/proxy/`。运行时 Hyperf 容器实例化的是该代理类——
代理类同名加载,原始源码文件不会再被加载。**因此这些源码文件绝不能进 AOT sources**:
tpc 若把原类注册为内置类,运行时代理类重声明同名类直接 `Fatal: Cannot redeclare class`。

**反推算法**(避免手工维护 `app/Controller/` 清单):
1. 逐个解析 `runtime/container/proxy/*.proxy.php` **文件内容**中的 `namespace` + `class`
   (**别用文件名下划线反推 FQCN**,类名/命名空间含下划线时会歧义);
2. 得精确 FQCN 后,按 `composer.json` 的 `autoload.psr-4` 前缀映射为项目相对路径
   (取**最长匹配前缀**,`str_replace('\\','/')` + `.php`),如 `App\Controller\IndexController`
   → `app/Controller/IndexController.php`;
3. 把这份文件列表注入 tpc 配置的 `ignore` 块,重新生成临时配置供 `tpc` 使用。

**载体**(`typephp-docker/` 三个文件,项目内自包含,源仓库 hyperf/repos/typephp-docker 同名):
- `proxy-exclude.php` —— 反推实现,stdout 每行输出一个相对路径;
- `build-aot-config.php` —— 读 `project.yml`,把反推结果注入 `ignore`(原配置无 `ignore:` 则追加),
  输出 `aot-project.yml`(写在项目根,原因见「问题排查」`getAbsolutePath`);
- `tpc-build.sh` —— 固化四步:①预热缓存(清空 `runtime/container` + php 解释器 +
  `SCAN_CACHEABLE=true`,产出缓存与代理类)→ ②反推排除 → ③`tpc aot-project.yml <args>` →
  ④确认产物。**注意**③之后每次编译都基于**重新预热后的新代理状态**,新增一个带 `#[Inject]`
  的类无需手工改任何清单。

**验证信号**:tpc 日志 `prepare completed: N source files` 的 N **不含**代理类对应文件
(如 `sources: app/Controller/` 下有 `Controller.php`+`IndexController.php` 两个文件、IndexController
带 Inject 时,N 只计入 Controller.php 等非代理文件);产物运行后 curl 命中接口且返回
**注入服务提供的值**(而非默认值),证明 DI 注入链路完整。

#### 注解扫描适配:SCAN_CACHEABLE 环境变量(不改源码 / 不 patch vendor)

Hyperf 注解收集发生在 TypePHP 编译**之前**的 php 解释器预热阶段,结果序列化到
`runtime/container`(scan.cache / aspects.cache / classes.cache)。产物运行阶段的
AOT 类对扫描器表现为"无源码类"(`getFileName()===false`)——**不要改 vendor 打补丁**。
正确做法:项目源码保持 `'scan_cacheable' => env('SCAN_CACHEABLE', false)`,
打包 / 运行时在 docker 内注入 `-e SCAN_CACHEABLE=true`:
  - **预热**(php 解释器):`docker run -e SCAN_CACHEABLE=true ... sh -c 'rm -rf runtime/container && php bin/hyperf.php'`
    → 缓存缺失时实时扫描并写入新缓存;
  - **运行**(AOT 产物):直接 `loadCache`,跳过 class traversal,无 TypeError。
打包链路已固化在 `typephp-docker/tpc-build.sh`(检测镜像 → 预热缓存+生成代理类 → **代理类反推
自动排除**(见上一节)→ `tpc aot-project.yml` → 输出运行命令),
全程 docker 内进行、只靠环境变量,不触碰 config / app / vendor;`sources` 用目录级
(如 `app/Controller/`),带 `#[Inject]` 的类由反推步骤自动排除。

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
> 进度来源:`hyperf/biz-skeleton`(Hyperf 3.2)实测,2026-09-26。
> 注解扫描适配方案纠正:由「patch vendor」改为「**不改源码/vendor,docker 内 env `SCAN_CACHEABLE=true`
> + 预热缓存」**,打包链路固化于 `typephp-docker/tpc-build.sh`(M5 产物化已完成)。

1. **M1 单文件环路 ✅**:写含 `main(): void` 的 hello 编译并在 docker 内运行 → 验证镜像/挂载/产物链条。
2. **M2 最小 Swoole HTTP 服务器 ✅**(风险解除):
   - 镜像构建时从源码编译安装 Swoole(ZTS),php.ini 加载——**产物可运行层级已经可用 Swoole 扩展**。
   - 写 `main(){ ... new Swoole\Coroutine\Http\Server('0.0.0.0', 9501) ... }` 编译,`docker run -p 9501:9501 ... ./swoole_server`,
     宿主 `curl localhost:9501` 通(需用 `\Swoole\Coroutine\run()` 包裹 start,见硬限制 5)。
   - **产物名注意**:tpc 会把输入文件名中的 `-` 转成 `_`(`swoole-server.php` → `swoole_server`),要改名用 `-o`。
3. **M3 Hyperf AOT 入口 ✅**(混合 AOT 模式验证通过):
   - 新建 `hyperf-aot/main.php`:`main(int $argc, array $argv): void` 内
     `require vendor/autoload → ClassLoader::init() → build container → get(ApplicationInterface) → run()`,
     常量 `defined() || define(...)` 守护。
   - `tpc hyperf-aot/main.php -o hyperf-server` → 产物启动后 `curl` 命中 controller(验证信号达成)。
   - `project.yml` 按「AOT 边界判定表」只放 `hyperf-aot` + 纯业务单元(如控制器),其余 app 走 fallback。
   - 注解扫描按「注解扫描适配」处理:**不改源码/vendor**,docker 内 env `SCAN_CACHEABLE=true` + 预热缓存。
4. **M4 完整 smoke test(待做)**:产物收束便携目录(见下),docker 内连 MySQL/Redis、命中 controller。
5. **M5 产物化 ✅**:`typephp-docker/tpc-build.sh` 固化「预热缓存(env `SCAN_CACHEABLE=true`)
   → `tpc project.yml` → 运行命令」,支持 `TYPEPHP_IMAGE` / `TYPEPHP_NO_BUILD` / `AOT_OUTPUT`;
   不改源码、不 patch vendor。
6. **M6 代理类反推自动化 ✅**(承接 M5,补齐 `#[Inject]` 场景):
   - 前置:预热会为带 `#[Inject]` 的类生成**同名代理类**到 `runtime/container/proxy/`,
     这些源码文件运行时被代理类替换,进 AOT 会 `Cannot redeclare class`(见「业务代码静态
     编译边界」判定表);
   - 实现:`typephp-docker/{proxy-exclude,build-aot-config}.php` +
     `tpc-build.sh` 新增「2/4 代理类反推」步骤,自动把反推结果注入 `ignore` 生成 `aot-project.yml`,
     `sources` 用**目录级**(`app/Controller/`),无需手工维护类清单;
   - 验证:`prepare completed: N source files` 不含代理类;产物 curl 命中接口且返回**注入
     服务的值**证明 DI 链路完整(php-demo 实测 `{"code":0,...,"message":"Hello foo"}`)。

### 产物形态与部署

便携目录 = ELF + `libphp.so` + `libphpx.so` + `php.ini` + `ext/*.so` + `lib/`(ldd 收集),
运行时需 `LD_LIBRARY_PATH` 含 phpx/libphp。非 Linux 宿主须在 docker 内跑 smoke test。

### 风险与缓解

| 风险 | 等级 | 缓解 / 回退 |
|---|---|---|
| Swoole 扩展在产物内不可用(ZTS ABI / 事件循环 / Embed SAPI 主循环冲突) | **高** | M2 前置验证;失败走 `php-builder` 私有运行时;再失败用 `-m ext` 把热点业务编译为扩展挂到原生 Hyperf |
| 注解/容器/代理动态面导致大量编译错(ProxyManager 动态生成类、AnnotationCollector 反射、`#[Inject]` 同名代理) | **高** | `SCAN_CACHEABLE=true` 预生成代理类;动态代码靠 ZendVM fallback;**带 `#[Inject]` 的类由「代理类反推」自动排除出 AOT**(M6,见上),不会进 sources |
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
| `-o <file>` | 指定产物文件名(默认输入 basename,`-`/非字母数字转 `_`;project.yml 场景覆盖 `name`) |
| `-m bin` | 二进制模式(默认,强制全局 `main(): void`) |
| `--build-dir <dir>` | 中间 C++/构建产物目录(默认按输入名生成) |

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
- **产物内框架启动报 `Filesystem::lastModified(... false ...)` TypeError**:运行未注入 `SCAN_CACHEABLE=true` / 缓存缺失,注解扫描实时遍历到 AOT 类。改用 `-e SCAN_CACHEABLE=true` 运行并确保先预热 `runtime/container`(见「注解扫描适配」,别改 vendor)。
- **启动报 `Swoole short function names must be disabled`**:php.ini 加 `swoole.use_shortname=Off`(挂载到容器 conf.d)。
- **报 `API must be called in the coroutine`**:Swoole 5+ 需 `\Swoole\Coroutine\run()` 包裹 `server->start()`。
- **vendor 包内 publish/tests/docs 文件顶层 `return []` 报 `Stmt_Return`**:在 project.yml 的 `ignore` 排除(`vendor/*/publish`、`vendor/*/tests`、`vendor/*/docs`)。
- **产物运行报 `Cannot redeclare class App\Controller\IndexController`**:带 `#[Inject]` 的类被写进了 AOT sources,预热生成了同名代理类,运行时同名替换冲突。解法:这类源码文件应从 sources 排除(由 tpc-build.sh「代理类反推」自动排除,见「业务代码静态编译边界」)。
- **tpc 报 `getAbsolutePath(): Return value must be of type string, bool returned`**:tpc **以配置文件所在目录**为基准解析 `sources`/`ignore` 的相对路径。临时配置(如反推生成的 `aot-project.yml`)必须放在项目根,不能放 `runtime/` 子目录(否则按 `runtime/app/...` 找文件 realpath 失败)。
- **`project.yml` 的 `name:` 产物名错乱**:`name: hyperf-server  # 注释` 的行内注释会被脚本整体抓走(`awk -F': '`),产物名变成含注释的乱串。`name:` 行保持纯键值、注释移到独立行。
- **产物名 `-` 被转 `_`**:`swoole-server.php` → `swoole_server`;需自定义名字用 `-o`。

## 参考

- 官方 TypePHP 文档:<https://www.swoole.com/aot/docs>
- Packagist 包:<https://packagist.org/packages/swoole/typephp>
- 源码仓库:<https://github.com/swoole/typephp.git>
- TypePHP 不兼容特性清单(源码 `docs/zh-cn/INCOMPATIBLE_PHP_FEATURES.md`)
- Webman 二进制构建插件 <https://github.com/tinywan/webman-typephp>(同构框架编译先例)