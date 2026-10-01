<?php
declare(strict_types=1);
require dirname(__DIR__) . '/src/bootstrap.php';

use LocalLife\{ApiException, Auth, Config, Security, SupabaseClient};

$error = null; $admin = null; $data = []; $detail = null; $factors = [];
$page = is_string($_GET['page'] ?? null) ? $_GET['page'] : 'dashboard';
$publicPages = ['login','signup','verify-email','forgot','callback'];
$resources = ['users','providers','categories','bookings','reviews','disputes','refunds','audit'];
$titles = ['dashboard'=>'Overview','users'=>'User management','providers'=>'Provider verification','categories'=>'Service categories','bookings'=>'Bookings & orders','reviews'=>'Review moderation','disputes'=>'Disputes','refunds'=>'Refund requests','analytics'=>'Analytics & reports','audit'=>'Audit trail','login'=>'Welcome back','signup'=>'Activate admin account','mfa'=>'Verify your identity','forgot'=>'Reset your password','reset'=>'Choose a new password','callback'=>'Account verification','document'=>'Credential document'];
$redirect = static function(string $destination): never { header('Location: ' . $destination, true, 303); exit; };
$titles['verify-email'] = 'Verify your email';
try {
    $config = new Config(dirname(__DIR__));
    Security::start($config);
    $api = new SupabaseClient($config); $auth = new Auth($api, $config);
    foreach ([$_GET,$_POST] as $input) { foreach ($input as $value) { if (!is_string($value)) { throw new ApiException(400,'Invalid request data.'); } } }
    if (!isset($titles[$page])) { http_response_code(404); $page='dashboard'; throw new ApiException(404,'Page not found.'); }
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        Security::checkCsrf();
        $action = is_string($_POST['action'] ?? null) ? $_POST['action'] : '';
        if ($action === 'login') { $auth->login(trim((string)($_POST['email'] ?? '')), (string)($_POST['password'] ?? '')); $redirect(url('mfa')); }
        if ($action === 'signup') {
            $auth->signup(trim((string)($_POST['email'] ?? '')),(string)($_POST['password'] ?? ''),(string)($_POST['confirm'] ?? ''));
            if(!empty($_SESSION['auth'])) { $redirect(url('mfa')); }
            $_SESSION['flash']='Check your email and enter its verification code. You will then set up your authenticator for admin sign-in.';
            $redirect(url('verify-email'));
        }
        if ($action === 'verify_email') { $auth->verifyEmailCode(trim((string)($_POST['code'] ?? ''))); $redirect(url('mfa')); }
        if ($action === 'resend_email') { $auth->resendEmailCode((string)($_POST['email'] ?? '')); $_SESSION['flash']='If confirmation is pending, a new email is on its way. Use its newest code.'; $redirect(url('verify-email')); }
        if ($action === 'logout') { $auth->logout(); $redirect(url('login')); }
        if ($action === 'recover') { $auth->recover(trim((string)($_POST['email'] ?? ''))); $_SESSION['flash']='If this account is registered, a reset link will arrive by email. Open it in this browser.'; $redirect(url('forgot')); }
        if ($action === 'enroll') { $auth->enroll(); $redirect(url('mfa')); }
        if ($action === 'verify') { $auth->verify((string)($_POST['factor_id'] ?? ''), trim((string)($_POST['code'] ?? ''))); $redirect(url(!empty($_SESSION['password_recovery']) ? 'reset' : 'dashboard')); }
        if ($action === 'reset') { $auth->resetPassword((string)($_POST['password'] ?? ''), (string)($_POST['confirm'] ?? '')); $_SESSION['flash']='Password updated. Sign in with your new password.'; $redirect(url('login')); }
        $admin = $auth->requireSession();
        $mutations = ['user_status','provider_verify','certificate_verify','category_save','category_delete','booking_status','review_moderate','dispute_open','dispute_resolve','refund_request'];
        if (!in_array($action, $mutations, true)) { throw new ApiException(400,'Unknown action.'); }
        $id = trim((string)($_POST['record_id'] ?? ''));
        $version = $_POST['version'] ?? null;
        if ($version === '') { $version = null; }
        if ($version !== null && (!is_string($version) || !preg_match('/^[a-f0-9]{32}$/', $version))) { throw new ApiException(400,'Invalid record version.'); }
        $payload = array_intersect_key($_POST, array_flip(['reason','active','status','verified','name','description','color','parent_id','display_order','decision','subject','amount']));
        foreach ($payload as $value) { if (!is_string($value)) { throw new ApiException(400,'Invalid form data.'); } }
        $uploadedIcon = null;
        if ($action === 'category_save' && isset($_FILES['icon_file']) && $_FILES['icon_file']['error'] !== UPLOAD_ERR_NO_FILE) {
            $file=$_FILES['icon_file'];
            if ($file['error']!==UPLOAD_ERR_OK || $file['size']>1048576 || !is_uploaded_file($file['tmp_name'])) { throw new ApiException(400,'Choose a PNG, JPEG or WebP icon up to 1 MB.'); }
            $mime=(new finfo(FILEINFO_MIME_TYPE))->file($file['tmp_name']);
            $extensions=['image/png'=>'png','image/jpeg'=>'jpg','image/webp'=>'webp'];
            $image=isset($extensions[$mime]) ? @getimagesize($file['tmp_name']) : false;
            if (!$image || ($image['mime'] ?? '')!==$mime || $image[0]>2000 || $image[1]>2000) { throw new ApiException(400,'Choose a valid PNG, JPEG or WebP image up to 2000 × 2000 pixels.'); }
            $uploadedIcon=bin2hex(random_bytes(16)).'.'.$extensions[$mime];
            $api->upload('/storage/v1/object/category-icons/'.$uploadedIcon,file_get_contents($file['tmp_name']),$mime,$_SESSION['auth']['access_token']);
            $payload['icon_url']=$config->supabaseUrl.'/storage/v1/object/public/category-icons/'.$uploadedIcon;
        }
        try { $result = $api->rpc('admin_mutate',['action_name'=>$action,'record_id'=>$id === '' ? null : Security::uuid($id),'expected_version'=>$version,'payload'=>$payload]); }
        catch (Throwable $failure) {
            if($uploadedIcon!==null) { try { $api->request('DELETE','/storage/v1/object/category-icons',['prefixes'=>[$uploadedIcon]],$_SESSION['auth']['access_token']); } catch(Throwable) { error_log('Unable to remove an unused category icon.'); } }
            throw $failure;
        }
        $_SESSION['flash']=$result['message'];
        $redirect(url(in_array($page,$resources,true) ? $page : 'dashboard'));
    }
    if ($page === 'callback') { $auth->callback((string)($_GET['code'] ?? '')); $redirect(url('mfa')); }
    if (!in_array($page,$publicPages,true)) {
        $admin = $auth->requireSession($page !== 'mfa');
        if ($page === 'document') {
            $document=$api->rpc('admin_document',['record_id'=>Security::uuid((string)($_GET['id'] ?? ''))]);
            $path=implode('/',array_map('rawurlencode',explode('/',$document['path'])));
            $signed=$api->request('POST','/storage/v1/object/sign/provider-documents/'.$path,['expiresIn'=>60],$_SESSION['auth']['access_token']);
            $signedPath=$signed['signedURL'] ?? $signed['signedUrl'] ?? '';
            if (!str_starts_with($signedPath,'/object/sign/provider-documents/')) { throw new ApiException(502,'Unable to open this document.'); }
            $redirect($config->supabaseUrl.'/storage/v1'.$signedPath);
        }
        if ($page === 'mfa') {
            if ($admin['mfa_verified']) { $redirect(url(!empty($_SESSION['password_recovery']) ? 'reset' : 'dashboard')); }
            $factors=$auth->factors();
        } elseif ($page === 'reset' && empty($_SESSION['password_recovery'])) { $redirect(url('dashboard')); }
        elseif (in_array($page,['dashboard','analytics'],true)) {
            $from = (string)($_GET['from'] ?? date('Y-m-01')); $to = (string)($_GET['to'] ?? date('Y-m-d'));
            foreach ([$from,$to] as $date) {
                if (!preg_match('/^(\d{4})-(\d{2})-(\d{2})$/',$date,$parts) || !checkdate((int)$parts[2],(int)$parts[3],(int)$parts[1])) { throw new ApiException(400,'Use valid dates.'); }
            }
            $category=trim((string)($_GET['category_id'] ?? '')); $provider=trim((string)($_GET['provider_id'] ?? '')); $region=trim((string)($_GET['region'] ?? ''));
            if(mb_strlen($region)>100) { throw new ApiException(400,'Choose a valid region.'); }
            $data=$api->rpc('admin_analytics',['date_from'=>$from,'date_to'=>$to,'category_filter'=>$category===''?null:Security::uuid($category),'region_filter'=>$region===''?null:$region,'provider_filter'=>$provider===''?null:Security::uuid($provider)]);
        } elseif (in_array($page,$resources,true)) {
            $data=$api->rpc('admin_list',['resource'=>$page,'search'=>mb_substr((string)($_GET['q'] ?? ''),0,100),'status_filter'=>(string)($_GET['status'] ?? ''),'page_number'=>max(1,(int)($_GET['p'] ?? 1))]);
            if (!empty($_GET['id'])) { $detail=$api->rpc('admin_detail',['resource'=>$page,'record_id'=>Security::uuid((string)$_GET['id'])]); }
            if ($page==='categories') {
                $categoryChoices=[];
                for($i=1;$i<=100;$i++) {
                    $chunk=$api->rpc('admin_list',['resource'=>'categories','page_number'=>$i]);
                    $categoryChoices=array_merge($categoryChoices,$chunk['items']);
                    if(count($categoryChoices)>=$chunk['total']) { break; }
                }
            }
        }
        if (isset($_GET['export'])) {
            if (!in_array($page,['analytics','bookings'],true)) { throw new ApiException(400,'Export is unavailable for this page.'); }
            if (!in_array($_GET['export'],['1','csv','print'],true) || ($page!=='bookings' && $_GET['export']==='print')) { throw new ApiException(400,'Choose a supported report format.'); }
            if ($page==='bookings' && $data['total']>10000) { throw new ApiException(400,'Narrow your filters to export at most 10,000 bookings.'); }
            $reportItems=[];
            if($page==='bookings') {
                for($i=1;$i<=500;$i++) {
                    $chunk=$i===($data['page'] ?? 1)?$data:$api->rpc('admin_list',['resource'=>'bookings','search'=>mb_substr((string)($_GET['q'] ?? ''),0,100),'status_filter'=>(string)($_GET['status'] ?? ''),'page_number'=>$i]);
                    $reportItems=array_merge($reportItems,$chunk['items']);
                    if(count($reportItems)>10000) { throw new ApiException(400,'Narrow your filters to export at most 10,000 bookings.'); }
                    if(!$chunk['items'] || count($reportItems)>=$chunk['total']) {break;}
                }
                if($_GET['export']==='print') { require dirname(__DIR__).'/views/booking-report.php'; exit; }
            }
            $out=fopen('php://temp','w+'); fwrite($out,"\xEF\xBB\xBF");
            if($page==='analytics') {
                fputcsv($out,['Metric','Value'],',','"','');
                foreach($data as $key=>$value) { if(!is_array($value)) { fputcsv($out,[Security::csvCell($key),Security::csvCell($value)],',','"',''); } }
                fputcsv($out,[],',','"',''); fputcsv($out,['Date','Bookings','New users (global)','Gross collected MYR'],',','"','');
                foreach($data['daily'] as $day) { fputcsv($out,[$day['date'],$day['bookings'],$day['users'],$day['gross_collected'] ?? 0],',','"',''); }
                fputcsv($out,[],',','"',''); fputcsv($out,['Service category','Bookings','Completed','Gross collected MYR'],',','"','');
                foreach($data['categories'] ?? [] as $categoryRow) { fputcsv($out,array_map([Security::class,'csvCell'],[$categoryRow['category_name'],$categoryRow['bookings'],$categoryRow['completed'],$categoryRow['gross_collected']]),',','"',''); }
                fputcsv($out,[],',','"',''); fputcsv($out,['Provider','Bookings','Completed','Overall rating'],',','"','');
                foreach($data['providers'] ?? [] as $providerRow) { fputcsv($out,array_map([Security::class,'csvCell'],[$providerRow['business_name'],$providerRow['bookings'],$providerRow['completed'],$providerRow['overall_rating']]),',','"',''); }
                fputcsv($out,[],',','"',''); fputcsv($out,['Filter','Value'],',','"','');
                foreach($data['selected_filters'] ?? [] as $filter=>$value) { fputcsv($out,[Security::csvCell($filter),Security::csvCell($value)],',','"',''); }
            } else {
                fputcsv($out,['Booking ID','Customer','Provider','Service','Scheduled','Status','Amount MYR'],',','"','');
                foreach($reportItems as $item) { fputcsv($out,array_map([Security::class,'csvCell'],[$item['booking_id'],$item['customer_name'],$item['provider_name'],$item['service_name'],$item['scheduled_datetime'],$item['booking_status'],$item['total_amount']]),',','"',''); }
            }
            header('Content-Type: text/csv; charset=UTF-8'); header('Content-Disposition: attachment; filename="local-life-'.$page.'-'.date('Ymd').'.csv"');
            rewind($out);fpassthru($out);fclose($out); exit;
        }
    }
} catch (ApiException $exception) {
    if ($exception->apiCode==='EMAIL_CONFIRMATION_REQUIRED') { $_SESSION['flash']=$exception->getMessage(); $redirect(url('verify-email')); }
    if ($exception->apiCode==='MFA_REQUIRED') { $redirect(url('mfa')); }
    if ($exception->status===401 && !in_array($page,$publicPages,true)) { $_SESSION['flash']=$exception->getMessage(); $redirect(url('login')); }
    http_response_code($exception->status >= 400 && $exception->status < 600 ? $exception->status : 400);
    $error=$exception->getMessage();
    if ($page==='mfa' && !empty($_SESSION['auth'])) {
        try { $admin=$auth->requireSession(false); $factors=$auth->factors(); }
        catch (ApiException) { unset($_SESSION['auth'],$_SESSION['admin'],$_SESSION['enrollment']); $redirect(url('login')); }
    }
} catch (Throwable $exception) {
    http_response_code(500);
    $reference=bin2hex(random_bytes(4));
    error_log('Admin error '.$reference.' '.get_class($exception));
    $error=isset($config) ? 'Something went wrong. Please retry. Reference: '.$reference : $exception->getMessage();
}
$flash=$_SESSION['flash'] ?? null; unset($_SESSION['flash']);
require dirname(__DIR__).'/views/layout.php';
