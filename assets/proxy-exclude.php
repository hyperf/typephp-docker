<?php

declare(strict_types=1);

/**
 * proxy-exclude.php — 反推「运行时被 Hyperf 同名代理类替换、不应进 AOT」的源码文件。
 *
 * 原理:Hyperf 预热(php bin/hyperf.php,SCAN_CACHEABLE=true)会把需要代理的类(如带
 * #[Inject] 属性注入的类)生成同名代理类到 runtime/container/proxy/<FQCN 下划线化>.proxy.php。
 * 运行时容器实例化的是该代理类(同名加载),原源码文件不会被加载 → 因此这些源码文件
 * 绝不能进入 tpc 的 AOT sources(否则 tpc 把原类注册为内置类,运行时代理类重声明同名类
 * 直接 Fatal: Cannot redeclare class)。
 *
 * 本工具逐个解析 proxy 文件内容中的 namespace + class 得精确 FQCN(不用文件名下划线反推,
 * 避免类名/命名空间含下划线时歧义),再按 composer.json 的 autoload.psr-4 映射为相对路径,
 * stdout 每行输出一个相对项目根的文件路径(如 app/Controller/IndexController.php)。
 *
 * 载体:本文件位于 SKILL 的 assets/ 下(自包含),由 scripts/tpc-build.sh 在容器内调用(见
 * tpc-build.sh 步骤 2,装配到 /opt/skill/proxy-exclude.php)。
 *
 * 用法:
 *   php assets/proxy-exclude.php <项目根>
 */

$root = $argv[1] ?? getcwd();
$proxyDir = $root . '/runtime/container/proxy';
if (!is_dir($proxyDir)) {
    exit(0); // 无代理类,输出为空
}

$composer = json_decode((string) file_get_contents($root . '/composer.json'), true);
$psr4 = $composer['autoload']['psr-4'] ?? [];

$excludes = [];
foreach (glob($proxyDir . '/*.proxy.php') ?: [] as $file) {
    $src = (string) file_get_contents($file);

    // 提取 namespace(App\Controller)与类名(IndexController)
    if (!preg_match('/^namespace\s+([^;]+);/m', $src, $m)) {
        fwrite(STDERR, "注: 跳过无法解析 namespace 的代理文件: {$file}\n");
        continue;
    }
    $ns = trim($m[1]);
    if (!preg_match('/^(?:final\s+|abstract\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)(?:<|\s|$)/m', $src, $m2)) {
        fwrite(STDERR, "注: 跳过无法解析 class 的代理文件: {$file}\n");
        continue;
    }
    $class = $m2[1];
    $fqcn = $ns . '\\' . $class;

    // 按 psr-4 前缀映射为相对路径(取最长匹配前缀)
    $best = null;
    foreach ($psr4 as $prefix => $dir) {
        $prefix = rtrim((string) $prefix, '\\');
        $probe = $prefix . '\\';
        if ($fqcn === $prefix || str_starts_with($fqcn, $probe)) {
            $cand = [strlen($prefix), rtrim(str_replace('\\', '/', (string) $dir), '/'), $prefix];
            if ($best === null || $cand[0] > $best[0]) {
                $best = $cand;
            }
        }
    }
    if ($best === null) {
        fwrite(STDERR, "注: 代理类 {$fqcn} 未命中 composer autoload.psr-4,跳过(非业务代理?)\n");
        continue;
    }
    [, $baseDir, $matchedPrefix] = $best;
    $rel = substr($fqcn, strlen($matchedPrefix) + 1); // 去掉 "前缀\" 后的类(含命名空间相对部分)
    $rel = str_replace('\\', '/', $rel) . '.php';
    $excludes[] = $baseDir . '/' . $rel;
}

sort($excludes);
echo implode("\n", array_unique($excludes));