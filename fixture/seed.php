<?php

// Deterministischer Seed: 20 Autoren x 5 Buecher = 100 Buecher.
$pdo = new PDO('sqlite:' . __DIR__ . '/var/data.db');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$pdo->exec('DELETE FROM book');
$pdo->exec('DELETE FROM author');

$insAuthor = $pdo->prepare('INSERT INTO author (id, name) VALUES (?, ?)');
$insBook = $pdo->prepare('INSERT INTO book (id, title, author_id) VALUES (?, ?, ?)');

$bookId = 1;
for ($a = 1; $a <= 20; ++$a) {
    $insAuthor->execute([$a, sprintf('Author %02d', $a)]);
    for ($b = 1; $b <= 5; ++$b) {
        $insBook->execute([$bookId, sprintf('Book %02d-%d', $a, $b), $a]);
        ++$bookId;
    }
}

echo 'seeded: ' . $pdo->query('SELECT COUNT(*) FROM book')->fetchColumn() . " books\n";
