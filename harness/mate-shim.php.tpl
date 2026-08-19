#!/usr/bin/env php
<?php
// Logging shim: records every invocation (timestamp, argv, cwd) as JSONL and then
// passes the call through to the real binary at mate.real. The runner reinstalls it
// after each reset, so the tagged fixture itself stays unmodified.
$__log = '__LOGPATH__';
@file_put_contents(
    $__log,
    json_encode(['ts' => date('c'), 'argv' => $argv, 'cwd' => getcwd()]) . PHP_EOL,
    FILE_APPEND | LOCK_EX
);
$__argv = $argv;
array_shift($__argv);
$__cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg(__DIR__ . '/mate.real');
foreach ($__argv as $__a) {
    $__cmd .= ' ' . escapeshellarg($__a);
}
passthru($__cmd, $__rc);
exit($__rc);
