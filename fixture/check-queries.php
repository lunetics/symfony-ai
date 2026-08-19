<?php

// Verifikation des synthetischen Testsets: Query-Zahl der letzten /books-Requests aus dem Profiler.
// Aufruf: php check-queries.php <app-dir>

$appDir = rtrim($argv[1] ?? '', '/');
if ('' === $appDir || !is_dir($appDir)) {
    fwrite(STDERR, "usage: php check-queries.php <app-dir>\n");
    exit(1);
}

require $appDir . '/vendor/autoload.php';
(new Symfony\Component\Dotenv\Dotenv())->bootEnv($appDir . '/.env');

$kernel = new App\Kernel('dev', true);
$kernel->boot();
$profiler = $kernel->getContainer()->get('profiler');

$tokens = $profiler->find('', '/books', 5, 'GET', null, null);
foreach ($tokens as $t) {
    $profile = $profiler->loadProfile($t['token']);
    if (!$profile || !$profile->hasCollector('db')) {
        continue;
    }
    $db = $profile->getCollector('db');
    printf("token=%s url=%s queries=%d\n", $t['token'], $t['url'], $db->getQueryCount());
}
