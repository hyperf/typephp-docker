<?php

declare(strict_types=1);

use Hyperf\Contract\ApplicationInterface;
use Hyperf\Di\ClassLoader;
use Psr\Container\ContainerInterface;
use Symfony\Component\Console\Application;

/**
 * TypePHP AOT 入口 —— bin/hyperf.php 的 AOT 化改造(源文件 bin/hyperf.php 保持不动)。
 *
 * 本文件由 typephp-compile SKILL 模板自动生成(scripts/tpc-build.sh 首次运行时复制到项目
 * hyperf-aot/main.php)。若项目入口结构不同(BASE_PATH 位置 / 容器定义方式),请自行调整。
 *
 * 适配点:
 *  - 去掉 shebang(tpc 不支持,会按 InlineHTML 报错);
 *  - tpc 二进制模式全局只允许声明,所有执行代码搬进 main();
 *  - 常量用 defined() || define(...) 守护;
 *  - $_SERVER['argv'] 传入 → 支持 ./hyperf_server start 这类子命令。
 */
function main(int $argc, array $argv): void
{
    defined('BASE_PATH') || define('BASE_PATH', dirname(__DIR__, 1));
    defined('SWOOLE_HOOK_FLAGS') || define('SWOOLE_HOOK_FLAGS', SWOOLE_HOOK_ALL);

    ini_set('display_errors', 'on');
    ini_set('display_startup_errors', 'on');
    error_reporting(E_ALL);
    date_default_timezone_set('Asia/Shanghai');

    $_SERVER['argv'] = $argv;

    require BASE_PATH . '/vendor/autoload.php';

    ClassLoader::init();
    /** @var ContainerInterface $container */
    $container = require BASE_PATH . '/config/container.php';
    /** @var Application $application */
    $application = $container->get(ApplicationInterface::class);
    $application->run();
}