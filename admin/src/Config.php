<?php
declare(strict_types=1);
namespace LocalLife;

final class Config
{
    public readonly string $environment;
    public readonly string $appUrl;
    public readonly string $supabaseUrl;
    public readonly string $key;
    public readonly string $storage;

    public function __construct(string $root)
    {
        $values = [];
        if (is_file($root . '/.env')) {
            foreach (file($root . '/.env', FILE_IGNORE_NEW_LINES) as $line) {
                $line = trim($line);
                if ($line === '' || str_starts_with($line, '#')) { continue; }
                if (str_contains($line, '=')) {
                    [$name, $value] = explode('=', $line, 2);
                    $values[trim($name)] = trim(trim($value), "\"'");
                }
            }
        }
        $get = static fn(string $key, string $fallback = ''): string => getenv($key) !== false ? (string)getenv($key) : ($values[$key] ?? $fallback);
        $this->environment = $get('APP_ENV', 'production');
        $this->appUrl = rtrim($get('APP_URL', 'http://127.0.0.1:8088'), '/');
        $this->supabaseUrl = rtrim($get('SUPABASE_URL'), '/');
        $this->key = $get('SUPABASE_PUBLISHABLE_KEY');
        $this->storage = $root . '/var';
        if (!$this->supabaseUrl || !$this->key || $this->key === 'replace-with-your-publishable-key') {
            throw new \RuntimeException('Copy admin/.env.example to admin/.env and configure the Supabase publishable key.');
        }
        if ($this->environment !== 'test' && !preg_match('~^https://[a-z0-9-]+\.supabase\.co$~', $this->supabaseUrl)) {
            throw new \RuntimeException('SUPABASE_URL must be the HTTPS URL of your hosted Supabase project.');
        }
        if (str_starts_with($this->key, 'sb_secret_')) { throw new \RuntimeException('Use a publishable key, never a secret key.'); }
        if (substr_count($this->key, '.') === 2) {
            $parts = explode('.', $this->key);
            $claims = json_decode(base64_decode(strtr($parts[1], '-_', '+/'), true) ?: '{}', true);
            if (($claims['role'] ?? '') !== 'anon') { throw new \RuntimeException('Only an anon or publishable key may be used by the admin application.'); }
        }
        if ($this->environment === 'production' && !str_starts_with($this->appUrl, 'https://')) {
            throw new \RuntimeException('Production requires an HTTPS APP_URL.');
        }
        if (!is_dir($this->storage)) { mkdir($this->storage, 0700, true); }
    }
}
