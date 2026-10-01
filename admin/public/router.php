<?php
declare(strict_types=1);
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
if (in_array($path, ['/assets/admin.css', '/assets/admin.js', '/assets/report.css'], true)) { return false; }
require __DIR__ . '/index.php';
