<?php
declare(strict_types=1);
namespace LocalLife;

final class Auth
{
    public function __construct(private readonly SupabaseClient $api, private readonly Config $config) {}

    public function login(string $email, string $password): void
    {
        Security::throttle($this->config, 'login:' . ($_SERVER['REMOTE_ADDR'] ?? 'local') . ':' . strtolower($email));
        if (!filter_var($email, FILTER_VALIDATE_EMAIL) || $password === '') { throw new ApiException(400, 'Enter your email and password.'); }
        try {
            $tokens = $this->api->request('POST', '/auth/v1/token?grant_type=password', ['email' => $email, 'password' => $password]);
            $this->saveTokens($tokens);
            $_SESSION['admin'] = $this->api->rpc('admin_identity');
        } catch (ApiException $exception) {
            unset($_SESSION['auth'], $_SESSION['admin']);
            if ($exception->apiCode === 'email_not_confirmed') {
                $this->api->rpc('admin_registration_check', ['invited_email' => $email]);
                $_SESSION['pending_email'] = strtolower(trim($email));
                $_SESSION['pending_email_started'] = time();
                throw new ApiException(403, 'Confirm your email using the code from your signup email, or request a new code.', 'EMAIL_CONFIRMATION_REQUIRED');
            }
            throw new ApiException($exception->status === 429 ? 429 : 401, $exception->status === 429 ? $exception->getMessage() : 'Unable to sign in. Use a verified, invited administrator account.');
        }
        unset($_SESSION['enrollment'], $_SESSION['password_recovery'], $_SESSION['pkce_verifier'], $_SESSION['pkce_started'], $_SESSION['pkce_flow']);
        session_regenerate_id(true);
        $_SESSION['signed_in_at'] = time();
        $_SESSION['last_activity'] = time();
        $_SESSION['csrf'] = bin2hex(random_bytes(32));
    }

    public function saveTokens(array $tokens): void
    {
        if (empty($tokens['access_token']) || empty($tokens['refresh_token'])) { throw new ApiException(502, 'Authentication response was incomplete.'); }
        $_SESSION['auth'] = ['access_token' => $tokens['access_token'], 'refresh_token' => $tokens['refresh_token'], 'expires_at' => time() + (int)($tokens['expires_in'] ?? 3600)];
    }

    public function requireSession(bool $mfa = true): array
    {
        if (empty($_SESSION['auth'])) { throw new ApiException(401, 'Please sign in.'); }
        if (time() - ($_SESSION['last_activity'] ?? 0) > 1800 || time() - ($_SESSION['signed_in_at'] ?? 0) > 28800) {
            $this->logout(); throw new ApiException(401, 'Your session expired. Please sign in again.');
        }
        if ($_SESSION['auth']['expires_at'] < time() + 60) {
            try { $this->saveTokens($this->api->request('POST', '/auth/v1/token?grant_type=refresh_token', ['refresh_token' => $_SESSION['auth']['refresh_token']])); }
            catch (ApiException $e) { unset($_SESSION['auth'], $_SESSION['admin']); throw new ApiException(401, 'Please sign in again.'); }
        }
        // Validated by Supabase on every page; local session fields never grant database authority.
        $admin = $this->api->rpc('admin_identity');
        $_SESSION['admin'] = $admin;
        $_SESSION['last_activity'] = time();
        if ($mfa && !($admin['mfa_verified'] ?? false)) { throw new ApiException(403, 'Complete authenticator verification first.', 'MFA_REQUIRED'); }
        return $admin;
    }

    public function factors(): array
    {
        $user = $this->api->request('GET', '/auth/v1/user', null, $_SESSION['auth']['access_token']);
        return array_values(array_filter($user['factors'] ?? [], static fn(array $f): bool => ($f['factor_type'] ?? '') === 'totp' && ($f['status'] ?? '') === 'verified'));
    }

    public function enroll(): void
    {
        $this->requireSession(false);
        if ($this->factors()) { throw new ApiException(400, 'Use your existing authenticator.'); }
        if (empty($_SESSION['enrollment'])) {
            $_SESSION['enrollment'] = $this->api->request('POST', '/auth/v1/factors', ['factor_type' => 'totp', 'friendly_name' => 'Local Life Admin ' . date('YmdHis')], $_SESSION['auth']['access_token']);
        }
    }

    public function verify(string $factor, string $code): void
    {
        $this->requireSession(false);
        Security::throttle($this->config, 'mfa:' . ($_SESSION['admin']['user_id'] ?? '') . ':' . ($_SERVER['REMOTE_ADDR'] ?? 'local'));
        Security::uuid($factor);
        if (!preg_match('/^\d{6}$/', $code)) { throw new ApiException(400, 'Enter the six-digit authenticator code.'); }
        $allowed = array_column($this->factors(), 'id');
        if (isset($_SESSION['enrollment']['id'])) { $allowed[] = $_SESSION['enrollment']['id']; }
        if (!in_array($factor, $allowed, true)) { throw new ApiException(403, 'Choose one of your authenticator factors.'); }
        $challenge = $this->api->request('POST', '/auth/v1/factors/' . $factor . '/challenge', [], $_SESSION['auth']['access_token']);
        $tokens = $this->api->request('POST', '/auth/v1/factors/' . $factor . '/verify', ['challenge_id' => $challenge['id'], 'code' => $code], $_SESSION['auth']['access_token']);
        $this->saveTokens($tokens);
        unset($_SESSION['enrollment']);
        session_regenerate_id(true);
        $this->requireSession();
    }

    public function recover(string $email): void
    {
        Security::throttle($this->config, 'recover:' . ($_SERVER['REMOTE_ADDR'] ?? 'local'));
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) { throw new ApiException(400, 'Enter a valid email address.'); }
        $verifier = rtrim(strtr(base64_encode(random_bytes(48)), '+/', '-_'), '=');
        $_SESSION['pkce_verifier'] = $verifier;
        $_SESSION['pkce_started'] = time();
        $_SESSION['pkce_flow'] = 'recovery';
        $challenge = rtrim(strtr(base64_encode(hash('sha256', $verifier, true)), '+/', '-_'), '=');
        $this->api->request('POST', '/auth/v1/recover?redirect_to=' . rawurlencode($this->config->appUrl . '/?page=callback'), ['email' => $email, 'code_challenge' => $challenge, 'code_challenge_method' => 's256']);
    }

    public function signup(string $email, string $password, string $confirm): void
    {
        Security::throttle($this->config, 'signup:' . ($_SERVER['REMOTE_ADDR'] ?? 'local'));
        if (!filter_var($email, FILTER_VALIDATE_EMAIL) || strlen($password)<12 || strlen($password)>128 || $password!==$confirm) {
            throw new ApiException(400,'Enter a valid email and matching passwords of 12–128 characters.');
        }
        $this->logout();
        $this->api->rpc('admin_registration_check', ['invited_email' => $email]);
        $verifier = rtrim(strtr(base64_encode(random_bytes(48)), '+/', '-_'), '=');
        $_SESSION['pkce_verifier']=$verifier; $_SESSION['pkce_started']=time(); $_SESSION['pkce_flow']='signup';
        $challenge=rtrim(strtr(base64_encode(hash('sha256',$verifier,true)),'+/','-_'),'=');
        // No role is accepted from client metadata. The database invitation authorizes activation after email verification.
        $tokens=$this->api->request('POST','/auth/v1/signup?redirect_to='.rawurlencode($this->config->appUrl.'/?page=callback'),
            ['email'=>$email,'password'=>$password,'code_challenge'=>$challenge,'code_challenge_method'=>'s256']);
        $_SESSION['pending_email'] = strtolower(trim($email));
        $_SESSION['pending_email_started'] = time();
        $_SESSION['email_sent_at'] = time();
        if (!empty($tokens['access_token'])) {
            $this->saveTokens($tokens); $_SESSION['signed_in_at']=$_SESSION['last_activity']=time();
            try { $this->requireSession(false); }
            catch (ApiException $exception) { unset($_SESSION['auth'], $_SESSION['admin'], $_SESSION['enrollment'], $_SESSION['password_recovery']); throw $exception; }
            session_regenerate_id(true);
        }
    }

    public function resendEmailCode(string $email): void
    {
        $email = strtolower(trim($email));
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) { throw new ApiException(400, 'Enter your invited email address.'); }
        Security::throttle($this->config, 'email-resend:' . ($_SERVER['REMOTE_ADDR'] ?? 'local'));
        if (time() - ($_SESSION['email_sent_at'] ?? 0) < 60) { throw new ApiException(429, 'Wait one minute before requesting another code.'); }
        $this->api->rpc('admin_registration_check', ['invited_email' => $email]);
        $this->api->request('POST', '/auth/v1/resend', ['type' => 'signup', 'email' => $email,
            'email_redirect_to' => $this->config->appUrl . '/?page=callback']);
        $_SESSION['pending_email'] = $email;
        $_SESSION['pending_email_started'] = $_SESSION['email_sent_at'] = time();
    }

    public function verifyEmailCode(string $code): void
    {
        if (empty($_SESSION['pending_email']) || time() - ($_SESSION['pending_email_started'] ?? 0) > 3600) {
            throw new ApiException(400, 'Request a new code for your invited email to continue.');
        }
        if (!preg_match('/^[0-9]{6,10}$/', $code)) { throw new ApiException(400, 'Enter the complete numeric code from your email.'); }
        Security::throttle($this->config, 'email-verify:' . ($_SERVER['REMOTE_ADDR'] ?? 'local') . ':' . $_SESSION['pending_email']);
        $tokens = $this->api->request('POST', '/auth/v1/verify', ['type' => 'email', 'email' => $_SESSION['pending_email'], 'token' => $code]);
        // Auth has consumed the email code. A later profile-activation failure
        // must be retried through password sign-in, not by reusing this code.
        unset($_SESSION['pending_email'], $_SESSION['pending_email_started'], $_SESSION['email_sent_at'], $_SESSION['pkce_verifier'], $_SESSION['pkce_started'], $_SESSION['pkce_flow'], $_SESSION['password_recovery'], $_SESSION['enrollment']);
        try {
            $this->saveTokens($tokens);
            $_SESSION['signed_in_at'] = $_SESSION['last_activity'] = time();
            $this->requireSession(false);
        } catch (ApiException $exception) {
            unset($_SESSION['auth'], $_SESSION['admin'], $_SESSION['signed_in_at'], $_SESSION['last_activity']);
            throw new ApiException($exception->status, 'Your email is verified, but administrator activation could not complete. Sign in with your existing password to retry. If access is still denied, ask the project owner to check your invitation.', 'ADMIN_ACTIVATION_PENDING');
        }
        session_regenerate_id(true);
        $_SESSION['csrf'] = bin2hex(random_bytes(32));
    }

    public function callback(string $code): void
    {
        if (empty($_SESSION['pkce_verifier']) || time() - ($_SESSION['pkce_started'] ?? 0) > 3600) { throw new ApiException(400, 'Request another verification link and open it in this browser.'); }
        $tokens = $this->api->request('POST', '/auth/v1/token?grant_type=pkce', ['auth_code' => $code, 'code_verifier' => $_SESSION['pkce_verifier']]);
        $recovery=($_SESSION['pkce_flow'] ?? '')==='recovery';
        unset($_SESSION['pkce_verifier'], $_SESSION['pkce_started'],$_SESSION['pkce_flow']);
        $this->saveTokens($tokens);
        $_SESSION['signed_in_at'] = $_SESSION['last_activity'] = time();
        $_SESSION['password_recovery'] = $recovery;
        session_regenerate_id(true);
        try { $this->requireSession(false); }
        catch (ApiException $exception) { unset($_SESSION['auth'], $_SESSION['admin'], $_SESSION['enrollment'], $_SESSION['password_recovery']); throw $exception; }
    }

    public function resetPassword(string $password, string $confirm): void
    {
        $this->requireSession();
        if (empty($_SESSION['password_recovery'])) { throw new ApiException(403, 'Request a password reset first.'); }
        if (strlen($password) < 12 || strlen($password) > 128 || $password !== $confirm) { throw new ApiException(400, 'Use matching passwords of 12–128 characters.'); }
        $this->api->request('PUT', '/auth/v1/user', ['password' => $password], $_SESSION['auth']['access_token']);
        $this->logout();
    }

    public function logout(): void
    {
        if (!empty($_SESSION['auth']['access_token'])) {
            try { $this->api->request('POST', '/auth/v1/logout?scope=local', [], $_SESSION['auth']['access_token']); } catch (ApiException) { /* Local credentials are cleared even when the network is unavailable. */ }
        }
        $_SESSION = ['csrf' => bin2hex(random_bytes(32))];
        session_regenerate_id(true);
    }
}
