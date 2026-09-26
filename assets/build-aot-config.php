<?php

declare(strict_types=1);

/**
 * build-aot-config.php — 生成 tpc 实际使用的临时 project 配置。
 *
 * 在原始 project.yml 基础上,把「反推出的代理类排除清单」(见 proxy-exclude.php)
 * 注入到 ignore 块,输出到指定文件(项目根 aot-project.yml)。
 * 不在原 project.yml 上改动,保持源码树干净;排除清单随每次预热后的 runtime/container/proxy
 * 自动更新 —— 每新增一个带 #[Inject] 等注解的类,重新编译即自动排除,无需手工维护。
 *
 * 载体:本文件位于 SKILL 的 assets/ 下(自包含),由 scripts/tpc-build.sh 在容器内调用,
 * 装配到 /opt/skill/build-aot-config.php(内部 shell_exec 以 __DIR__ 相对调用 proxy-exclude.php,
 * 因此两文件必须处于同一目录)。
 *
 * 用法:
 *   php assets/build-aot-config.php <项目根> <输出配置文件路径>
 *   输出内容:原 project.yml + ignore 注入(若原配置无 ignore.块则追加)。
 */

$root = $argv[1] ?? getcwd();
$out = $argv[2] ?? ($root . '/aot-project.yml');
$srcYml = $root . '/project.yml';
if (!is_file($srcYml)) {
    fwrite(STDERR, "错误: 未找到 {$srcYml}\n");
    exit(1);
}

// 反推排除清单
$excludes = [];
$proxyDir = $root . '/runtime/container/proxy';
if (is_dir($proxyDir)) {
    $cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg(__DIR__ . '/proxy-exclude.php') . ' ' . escapeshellarg($root);
    $out_raw = shell_exec($cmd);
    if ($out_raw !== null && is_string($out_raw)) {
        $excludes = array_values(array_filter(array_map('trim', explode("\n", trim($out_raw)))));
    }
}

$lines = file($srcYml, FILE_IGNORE_NEW_LINES);

$injected = false;
$yml = '';
foreach ($lines as $line) {
    $yml .= $line . "\n";
    if (!$injected && trim($line) === 'ignore:') {
        if ($excludes) {
            foreach ($excludes as $e) {
                $yml .= "  - {$e}  # [aot-auto] proxy 反推:运行时被代理类替换,不进 AOT\n";
            }
        }
        $injected = true;
    }
}
if (!$injected && $excludes) {
    // 原配置没有 ignore 块,追加
    $yml .= "ignore:\n";
    foreach ($excludes as $e) {
        $yml .= "  - {$e}  # [aot-auto] proxy 反推:运行时被代理类替换,不进 AOT\n";
    }
}

file_put_contents($out, $yml);
fwrite(STDOUT, $excludes ? '排除 ' . count($excludes) . " 个代理类对应文件:\n  - " . implode("\n  - ", $excludes) . "\n" : "(无代理类排除项)\n");