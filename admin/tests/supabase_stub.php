<?php
declare(strict_types=1);

// Local contract fixture. This router is used only by run.php, never by the application.
$stateDir = (string)getenv('TEST_STATE_DIR');
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$method = $_SERVER['REQUEST_METHOD'];
$rawBody = file_get_contents('php://input') ?: '';
$body = json_decode($rawBody ?: '{}', true) ?? [];
$fixtureState = is_file($stateDir.'/fixture-state.json') ? json_decode(file_get_contents($stateDir.'/fixture-state.json'),true) : [];
$headers = array_change_key_case(getallheaders(), CASE_LOWER);
$token = substr((string)($headers['authorization'] ?? ''), 7);
$verified = $token === 'fixture-access-aal2';
$factor = '10000000-0000-4000-8000-000000000001';
$record = '20000000-0000-4000-8000-000000000001';
$version = str_repeat('a', 32);
file_put_contents($stateDir . '/requests.jsonl', json_encode(['method'=>$method,'path'=>$path,'query'=>$_GET,'body'=>$body,'token'=>$token,'content_type'=>$headers['content-type']??null,'content_bytes'=>strlen($rawBody)], JSON_THROW_ON_ERROR) . "\n", FILE_APPEND | LOCK_EX);
header('Content-Type: application/json');

function respond(array $value, int $status = 200): never {
    http_response_code($status); echo json_encode($value, JSON_THROW_ON_ERROR); exit;
}
function tokens(bool $verified = false): array {
    return ['access_token'=>$verified ? 'fixture-access-aal2' : 'fixture-access-aal1','refresh_token'=>$verified ? 'fixture-refresh-aal2' : 'fixture-refresh-aal1','expires_in'=>3600,'token_type'=>'bearer'];
}
function booking(int $index): array {
    global $fixtureState;
    $visual=!empty($fixtureState['visual_preview']);
    $customer=!empty($fixtureState['unsafe_booking_name']) && $index===1?'<script>alert(1)</script>':($visual?'Test Customer '.$index:($index===1?'=HYPERLINK("https://invalid.example")':'Customer '.$index));
    return ['booking_id'=>sprintf('30000000-0000-4000-8000-%012d',$index),'customer_name'=>$customer,'provider_name'=>$visual?'Fixture Plumbing':'+SUM(1,1)','service_name'=>$visual?'Tap repair':' @unsafe','scheduled_datetime'=>'2026-10-01T02:00:00+00:00','booking_status'=>'Pending','status'=>'Pending','total_amount'=>'80.00','payment_status'=>'Success','urgency'=>'Normal','created_at'=>'2026-10-01T00:00:00+00:00','version'=>str_repeat('a',32)];
}

if (($headers['apikey'] ?? '') !== 'sb_publishable_test_contract') { respond(['message'=>'Missing publishable API key'],401); }
if ($path === '/auth/v1/token' && $method === 'POST') {
    switch ($_GET['grant_type'] ?? '') {
        case 'password':
            if (!empty($fixtureState['email_unconfirmed'])) { respond(['code'=>400,'error_code'=>'email_not_confirmed','msg'=>'Email not confirmed'],400); }
            if (($body['password'] ?? '') !== 'test-password-only') { respond(['error_code'=>'invalid_credentials','msg'=>'Invalid login credentials'],400); }
            if (($body['email'] ?? '')==='customer@example.test') { respond(array_replace(tokens(),['access_token'=>'fixture-customer-token'])); }
            respond(tokens());
        case 'refresh_token': respond(tokens(($body['refresh_token'] ?? '')==='fixture-refresh-aal2'));
        case 'pkce':
            if (empty($body['code_verifier']) || !in_array($body['auth_code'] ?? '',['fixture-recovery-code','fixture-confirmation-code'],true)) { respond(['msg'=>'Invalid verification code'],400); }
            if (!empty($fixtureState['deny_activation'])) { respond(array_replace(tokens(),['access_token'=>'fixture-customer-token'])); }
            respond(tokens());
    }
}
if ($path === '/auth/v1/signup' && $method === 'POST') {
    if (!empty($fixtureState['signup_immediate_tokens'])) { respond(array_replace(tokens(),['access_token'=>!empty($fixtureState['deny_activation'])?'fixture-customer-token':'fixture-access-aal1'])); }
    respond(['id'=>'40000000-0000-4000-8000-000000000001','email'=>$body['email']],200);
}
if ($path === '/auth/v1/recover' && $method === 'POST') { respond([]); }
if ($path === '/auth/v1/resend' && $method === 'POST') { respond([]); }
if ($path === '/auth/v1/verify' && $method === 'POST') {
    if (($body['type'] ?? '')!=='email' || ($body['token'] ?? '')!=='123456') { respond(['error_code'=>'otp_expired','msg'=>'Invalid or expired code'],403); }
    respond(array_replace(tokens(),['access_token'=>!empty($fixtureState['deny_activation'])?'fixture-customer-token':'fixture-access-aal1']));
}
if ($path === '/rest/v1/rpc/admin_registration_check') {
    if (!empty($fixtureState['deny_registration'])) { respond(['code'=>'42501','message'=>'Use an unused invited admin email. Existing accounts should sign in.'],403); }
    respond(['eligible'=>true]);
}
if ($path === '/auth/v1/logout' && $method === 'POST') { respond([]); }
if ($path === '/auth/v1/user' && $method === 'GET') {
    respond(['id'=>'40000000-0000-4000-8000-000000000001','email'=>'admin@example.test','factors'=>!empty($fixtureState['factor_unverified'])?[]:[['id'=>$factor,'factor_type'=>'totp','status'=>'verified','friendly_name'=>'Test authenticator']]]);
}
if ($path === '/auth/v1/factors' && $method === 'POST') { respond(['id'=>$factor,'factor_type'=>'totp','totp'=>['secret'=>'TEST-SETUP-SECRET','qr_code'=>'<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><rect width="100" height="100"/></svg>','uri'=>'otpauth://totp/fixture']]); }
if ($path === '/auth/v1/user' && $method === 'PUT') {
    if (!$verified) { respond(['msg'=>'MFA required'],403); }
    respond(['id'=>'40000000-0000-4000-8000-000000000001']);
}
if ($path === '/auth/v1/factors/' . $factor . '/challenge' && $method === 'POST') { respond(['id'=>'challenge-fixture','expires_at'=>time()+300]); }
if ($path === '/auth/v1/factors/' . $factor . '/verify' && $method === 'POST') {
    if (($body['code'] ?? '')!=='123456' || ($body['challenge_id'] ?? '')!=='challenge-fixture') { respond(['msg'=>'Invalid authenticator code'],422); }
    $fixtureState['factor_unverified']=false;
    file_put_contents($stateDir.'/fixture-state.json',json_encode($fixtureState));
    respond(tokens(true));
}
if (preg_match('~^/storage/v1/object/category-icons/[a-f0-9]{32}\.png$~',(string)$path) && $method==='POST') {
    if (!$verified || ($headers['content-type']??'')!=='image/png') { respond(['message'=>'Verified PNG upload required'],403); }
    respond(['Key'=>substr((string)$path,strlen('/storage/v1/object/'))]);
}
if ($path==='/storage/v1/object/category-icons' && $method==='DELETE') {
    if (!$verified || empty($body['prefixes'])) { respond(['message'=>'Verified cleanup required'],403); }
    respond([]);
}
if ($path === '/storage/v1/object/sign/provider-documents/fake.pdf' && $method === 'POST') {
    if (!$verified || ($body['expiresIn'] ?? null)!==60) { respond(['message'=>'Short-lived verified access required'],403); }
    respond(['signedURL'=>'/object/sign/provider-documents/fake.pdf?token=fixture-signed-token']);
}
if ($path === '/rest/v1/rpc/admin_identity') {
    if ($token==='fixture-customer-token') { respond(['code'=>'42501','message'=>'An active administrator account is required'],403); }
    if (!in_array($token,['fixture-access-aal1','fixture-access-aal2'],true)) { respond(['code'=>'42501','message'=>'Authentication required'],401); }
    respond(['user_id'=>$record,'email'=>'admin@example.test','full_name'=>'Test Administrator','role_level'=>'super_admin','mfa_verified'=>$verified]);
}
if (str_starts_with((string)$path,'/rest/v1/rpc/')) {
    if (!$verified) { respond(['code'=>'42501','message'=>'Complete authenticator verification first'],403); }
    if ($path === '/rest/v1/rpc/admin_list') {
        $page = (int)($body['page_number'] ?? 1);
        $resource = $body['resource'] ?? '';
        if ($resource==='bookings' && ($fixtureState['fail_booking_page'] ?? null)===$page) { respond(['message'=>'Fixture downstream unavailable'],503); }
        $items = match ($resource) {
            'users'=>[['user_id'=>$record,'auth_user_id'=>'40000000-0000-4000-8000-000000000001','full_name'=>!empty($fixtureState['visual_preview'])?'Test Customer':'<script>alert(1)</script>','email'=>'user@example.test','phone'=>'+60123456789','role'=>'customer','is_active'=>true,'email_verified'=>true,'status'=>'Active','created_at'=>'2026-10-01T00:00:00+00:00','version'=>$version]],
            'providers'=>[['provider_id'=>$record,'user_id'=>$record,'full_name'=>'Test Provider','business_name'=>'Fixture Plumbing','email'=>'provider@example.test','business_license'=>'SSM-TEST','bio'=>'Qualified plumber','verification_status'=>'Pending','status'=>'Pending','is_active'=>true,'overall_rating'=>'4.8','total_reviews'=>12,'region'=>'Selangor','city'=>'Petaling Jaya','years_experience'=>5,'created_at'=>'2026-10-01T00:00:00+00:00','version'=>$version]],
            'categories'=>[['category_id'=>$record,'category_name'=>'Plumbing','description'=>'Household plumbing','icon_url'=>null,'color_code'=>'#F97316','parent_category_id'=>null,'parent_name'=>null,'display_order'=>1,'is_active'=>true,'status'=>'Active','service_count'=>3,'created_at'=>'2026-10-01T00:00:00+00:00','version'=>$version]],
            'bookings'=>array_map('booking',$page===1?range(1,20):($page===2?[21]:[])),
            'reviews'=>[['review_id'=>$record,'booking_id'=>$record,'customer_name'=>'Test Customer','provider_name'=>'Fixture Plumbing','rating_score'=>4,'review_comment'=>'Helpful service','is_flagged'=>true,'moderation_status'=>'visible','status'=>'Flagged','created_at'=>'2026-10-01T00:00:00+00:00','version'=>$version]],
            'disputes'=>[['dispute_id'=>$record,'booking_id'=>$record,'opened_by_name'=>'Test Customer','subject'=>'Service incomplete','description'=>'The booked service was not completed.','status'=>'Open','created_at'=>'2026-10-01T00:00:00+00:00','version'=>$version]],
            'refunds'=>[['refund_id'=>$record,'booking_id'=>$record,'payment_id'=>$record,'amount'=>'80.00','reason'=>'Service cancellation by provider','status'=>'Requested','created_at'=>'2026-10-01T00:00:00+00:00']],
            'audit'=>[['log_id'=>$record,'actor_name'=>'Test Administrator','actor_role'=>'admin','action'=>'provider_verify','status'=>'provider_verify','target_table'=>'provider_profiles','target_id'=>$record,'old_values'=>['verification_status'=>'Pending'],'new_values'=>['verification_status'=>'Verified'],'created_at'=>'2026-10-01T00:00:00+00:00']],
            default=>[],
        };
        respond(['items'=>$items,'total'=>$resource==='bookings'?21:count($items),'page'=>$page,'page_size'=>20]);
    }
    if ($path === '/rest/v1/rpc/admin_detail') {
        $resource=$body['resource'] ?? '';
        $common=['version'=>$version,'created_at'=>'2026-10-01T00:00:00+00:00','updated_at'=>'2026-10-01T00:00:00+00:00'];
        $detail=$common + match($resource) {
            'users'=>['user_id'=>$record,'email'=>'user@example.test','full_name'=>'Test Customer','phone'=>'+60123456789','role'=>'customer','is_active'=>true,'email_verified'=>true,'last_login_at'=>null,'actions'=>[]],
            'providers'=>['provider_id'=>$record,'user_id'=>$record,'business_name'=>'Fixture Plumbing','full_name'=>'Test Provider','email'=>'provider@example.test','business_license'=>'SSM-TEST','verification_status'=>'Pending','bio'=>'Qualified plumber','region'=>'Selangor','city'=>'Petaling Jaya','years_experience'=>5,'service_radius_km'=>10,'certifications'=>[['certification_id'=>$record,'certification_name'=>'Plumbing credential','issuer'=>'Fixture Institute','expiry_date'=>'2027-10-01','file_url'=>'provider-documents/fake.pdf','is_verified'=>false,'version'=>$version]],'hours'=>[['day_of_week'=>0,'start_time'=>'09:00:00','end_time'=>'17:00:00','is_active'=>true]],'portfolio'=>[]],
            'categories'=>['category_id'=>$record,'category_name'=>'Plumbing','description'=>'Household plumbing','color_code'=>'#F97316','parent_category_id'=>null,'display_order'=>1,'is_active'=>true],
            'bookings'=>booking(1)+['payment'=>['payment_id'=>$record,'payment_status'=>'Success','payment_amount'=>'80.00','payment_method'=>'FPX','fpx_transaction_ref'=>'FPX-FIXTURE','payment_timestamp'=>'2026-10-01T00:00:00+00:00','escrow_held'=>true,'receipt_url'=>null],'history'=>[['previous_status'=>null,'new_status'=>'Pending','created_at'=>'2026-10-01T00:00:00+00:00','notes'=>'Booked by customer']],'disputes'=>[],'customer_address'=>'Petaling Jaya','special_instructions'=>'Fix leaking tap'],
            'reviews'=>['review_id'=>$record,'booking_id'=>$record,'rating_score'=>4,'review_comment'=>'Helpful service','is_flagged'=>true,'is_verified_booking'=>true,'flag_reason'=>'Potential spam','moderation_status'=>'visible','moderation_reason'=>null],
            'disputes'=>['dispute_id'=>$record,'booking_id'=>$record,'subject'=>'Service incomplete','description'=>'The booked service was not completed.','status'=>'Open','resolution'=>null,'resolved_at'=>null],
            default=>[],
        };
        if ($resource==='providers' && !empty($fixtureState['expired_verified_certificate'])) {
            $detail['certifications'][0]['expiry_date']='2020-01-01';
            $detail['certifications'][0]['is_verified']=true;
        }
        respond($detail);
    }
    if ($path === '/rest/v1/rpc/admin_analytics') {
        $from=new DateTimeImmutable($body['date_from']); $to=new DateTimeImmutable($body['date_to']);
        if ($to<$from || $from->diff($to)->days>366) { respond(['code'=>'P0001','message'=>'Choose a date range of at most 367 days'],400); }
        $analytics=['from'=>$body['date_from'],'to'=>$body['date_to'],'timezone'=>'Asia/Kuala_Lumpur','users'=>12,'new_users'=>2,'bookings'=>21,'active_bookings'=>3,'pending_providers'=>1,'open_disputes'=>1,'flagged_reviews'=>1,'gross_collected'=>'1680.00','platform_fees'=>'168.00','refunds_requested'=>'80.00','avg_rating'=>'4.50','daily'=>[['date'=>'2026-10-01','bookings'=>2,'users'=>1,'gross_collected'=>'160.00']],'providers'=>[['business_name'=>'Fixture Plumbing','bookings'=>21,'completed'=>18,'overall_rating'=>'4.8']],'category_choices'=>[['category_id'=>$record,'category_name'=>'Plumbing','parent_category_id'=>null]],'region_choices'=>['Selangor','Kuala Lumpur'],'provider_choices'=>[['provider_id'=>$record,'business_name'=>'Fixture Plumbing','region'=>'Selangor']],'selected_filters'=>['category_id'=>$body['category_filter']??null,'region'=>$body['region_filter']??null,'provider_id'=>$body['provider_filter']??null],'categories'=>[['category_id'=>$record,'category_name'=>'Plumbing','bookings'=>21,'completed'=>18,'gross_collected'=>'1680.00']],'scope_note'=>'User registration and pending-provider metrics remain global. Booking, payment and performance metrics respect selected service filters.'];
        if (!empty($fixtureState['zero_bookings'])) {
            $analytics['bookings']=0; $analytics['gross_collected']='75.00';
            $analytics['daily']=[['date'=>'2026-10-01','bookings'=>0,'users'=>1,'gross_collected'=>'75.00']];
            $analytics['categories']=[['category_id'=>$record,'category_name'=>'Plumbing','bookings'=>0,'completed'=>0,'gross_collected'=>'75.00']];
            $analytics['providers']=[['business_name'=>'Fixture Plumbing','bookings'=>0,'completed'=>0,'overall_rating'=>'4.8']];
        }
        respond($analytics);
    }
    if ($path === '/rest/v1/rpc/admin_mutate') {
        if (($body['expected_version'] ?? '') === str_repeat('b',32)) { respond(['code'=>'40001','message'=>'This record changed. Reload before saving.'],409); }
        respond(['id'=>$record,'message'=>'Changes saved.']);
    }
    if ($path === '/rest/v1/rpc/admin_document') { respond(['path'=>'fake.pdf']); }
}
respond(['message'=>'Unexpected stub request: '.$method.' '.$path],404);
