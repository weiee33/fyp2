<?php
declare(strict_types=1);

date_default_timezone_set('Asia/Kuala_Lumpur');

spl_autoload_register(static function (string $class): void {
    $prefix = 'LocalLife\\';
    if (str_starts_with($class, $prefix)) {
        $path = __DIR__ . '/' . substr($class, strlen($prefix)) . '.php';
        if (is_file($path)) { require $path; }
    }
});

function e(mixed $value): string { return htmlspecialchars((string) ($value ?? ''), ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'); }
function money(mixed $value): string { return 'RM ' . number_format((float) ($value ?? 0), 2); }
function url(string $page, array $params = []): string { return '/?' . http_build_query(['page' => $page] + $params); }
function csrf(): string { return '<input type="hidden" name="csrf" value="' . e($_SESSION['csrf']) . '">'; }
function badge(mixed $value): string { return '<span class="badge badge-' . e(strtolower(preg_replace('/[^a-z0-9]+/i', '-', (string)$value))) . '">' . e($value) . '</span>'; }
function localDate(?string $value, string $format = 'd M Y, H:i'): string {
    if (!$value) { return '—'; }
    try { return (new DateTimeImmutable($value))->setTimezone(new DateTimeZone('Asia/Kuala_Lumpur'))->format($format); }
    catch (Exception) { return '—'; }
}
