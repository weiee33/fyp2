<?php
declare(strict_types=1);
namespace LocalLife;

final class Security
{
    public static function start(Config $config): void
    {
        ini_set('session.use_strict_mode', '1');
        ini_set('session.use_only_cookies', '1');
        ini_set('session.save_path', $config->storage);
        session_name('locallife_admin');
        session_set_cookie_params(['lifetime' => 0, 'path' => '/', 'secure' => str_starts_with($config->appUrl, 'https://'), 'httponly' => true, 'samesite' => 'Lax']);
        session_start();
        $_SESSION['csrf'] ??= bin2hex(random_bytes(32));
        header('Cache-Control: no-store, private');
        header('X-Content-Type-Options: nosniff');
        header('X-Frame-Options: DENY');
        header('Referrer-Policy: no-referrer');
        header("Permissions-Policy: camera=(), microphone=(), geolocation=()");
        header("Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");
        if (str_starts_with($config->appUrl, 'https://')) { header('Strict-Transport-Security: max-age=31536000'); }
    }

    public static function checkCsrf(): void
    {
        if (!isset($_POST['csrf']) || !is_string($_POST['csrf']) || !hash_equals($_SESSION['csrf'], $_POST['csrf'])) {
            throw new ApiException(403, 'Your form expired. Reload the page and try again.');
        }
    }

    public static function throttle(Config $config, string $identifier): void
    {
        $file = $config->storage . '/rate-' . hash('sha256', $identifier) . '.json';
        $handle = fopen($file, 'c+');
        if (!$handle || !flock($handle, LOCK_EX)) { throw new ApiException(503, 'Please try again later.'); }
        try {
            $state = json_decode(stream_get_contents($handle) ?: '{}', true) ?: [];
            if (($state['until'] ?? 0) < time()) { $state = ['count' => 0, 'until' => time() + 900]; }
            if ($state['count'] >= 10) { throw new ApiException(429, 'Too many attempts. Please wait 15 minutes.'); }
            $state['count']++;
            rewind($handle); ftruncate($handle, 0); fwrite($handle, json_encode($state, JSON_THROW_ON_ERROR));
        } finally { flock($handle, LOCK_UN); fclose($handle); }
    }

    public static function uuid(string $value): string
    {
        if (!preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $value)) { throw new ApiException(400, 'Invalid record identifier.'); }
        return $value;
    }

    public static function csvCell(mixed $value): string
    {
        $text = (string)($value ?? '');
        return preg_match('/^[\s]*[=+\-@\t\r]/u', $text) ? "'" . $text : $text;
    }
}
