<?php

/**
 * 最小 Swoole Coroutine HTTP 服务器
 * —— M2:验证 TypePHP 编译产物内 Swoole 扩展可用性
 */

function main(): void
{
    \Swoole\Coroutine\run(function () {
        $http = new Swoole\Coroutine\Http\Server('0.0.0.0', 9501);
        $http->handle('/', function ($request, $response) {
            $response->header('Content-Type', 'text/plain');
            $response->end("Hello TypePHP Swoole\n");
        });
        echo "Swoole server listening on 9501\n";
        $http->start();
    });
}