<?php
declare(strict_types=1);
namespace LocalLife;

final class SupabaseClient
{
    public function __construct(private readonly Config $config) {}

    public function request(string $method, string $path, ?array $body = null, ?string $token = null): array
    {
        return $this->send($method, $path, $body === null ? null : json_encode($body ?: new \stdClass(), JSON_THROW_ON_ERROR), $token, 'application/json');
    }

    public function upload(string $path, string $content, string $mime, string $token): array
    {
        return $this->send('POST', $path, $content, $token, $mime);
    }

    private function send(string $method, string $path, ?string $body, ?string $token, string $contentType): array
    {
        if (!str_starts_with($path, '/') || str_starts_with($path, '//')) { throw new \InvalidArgumentException('Invalid API path'); }
        $curl = curl_init($this->config->supabaseUrl . $path);
        $headers = ['apikey: ' . $this->config->key, 'Accept: application/json', 'Content-Type: ' . $contentType];
        if ($token) { $headers[] = 'Authorization: Bearer ' . $token; }
        curl_setopt_array($curl, [CURLOPT_CUSTOMREQUEST => $method, CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CONNECTTIMEOUT => 8, CURLOPT_TIMEOUT => 25, CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_HTTPHEADER => $headers, CURLOPT_SSL_VERIFYPEER => true, CURLOPT_SSL_VERIFYHOST => 2]);
        if (defined('CURLSSLOPT_NATIVE_CA')) { curl_setopt($curl, CURLOPT_SSL_OPTIONS, CURLSSLOPT_NATIVE_CA); }
        if ($body !== null) { curl_setopt($curl, CURLOPT_POSTFIELDS, $body); }
        $raw = curl_exec($curl);
        $status = (int)curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
        if ($raw === false) { curl_close($curl); throw new ApiException(503, 'The service could not be reached. Please try again.'); }
        curl_close($curl);
        $data = $raw === '' ? [] : json_decode($raw, true);
        if ($status < 200 || $status >= 300) {
            $code = (string)($data['error_code'] ?? $data['code'] ?? '');
            $message = (string)($data['message'] ?? $data['msg'] ?? $data['error_description'] ?? 'The request could not be completed.');
            if (!in_array($code, ['P0001','P0002','40001','42501'], true) || str_starts_with($path, '/auth/')) {
                $message = $status === 429 ? 'Too many attempts. Please wait before trying again.' : 'The request could not be completed. Check your details and try again.';
            }
            if ($code === '23503') { $message = 'This record is still referenced. Deactivate it instead.'; }
            if ($code === '23505') { $message = 'A matching record or pending request already exists.'; }
            if (in_array($code, ['otp_expired','otp_disabled'], true)) { $message = 'This code is invalid or expired. Request a new email code and try again.'; }
            if ($code === 'mfa_verification_failed') { $message = 'The authenticator code is incorrect or expired. Enter the current code from your app.'; }
            throw new ApiException($status, $message, $code);
        }
        if (!is_array($data)) { throw new ApiException(502, 'Unexpected response from the service.'); }
        return $data;
    }

    public function rpc(string $name, array $params = []): array
    {
        if (!preg_match('/^admin_[a-z_]+$/', $name)) { throw new \InvalidArgumentException('Invalid operation'); }
        return $this->request('POST', '/rest/v1/rpc/' . $name, $params, $_SESSION['auth']['access_token'] ?? null);
    }
}
