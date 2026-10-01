<?php
declare(strict_types=1);

/** HTTP regression tests against an isolated copy of the admin site and local Supabase contracts.
 * Run: .tools/php/php.exe -d extension_dir=.tools/php/ext admin/tests/run.php
 * No external service, Composer, real credentials or source application files are modified.
 */
if (!extension_loaded('curl') || !extension_loaded('mbstring')) {
    fwrite(STDERR, "Enable curl and mbstring before running the suite.\n"); exit(2);
}
require dirname(__DIR__) . '/src/bootstrap.php';

$root = dirname(__DIR__);
$runtime = sys_get_temp_dir() . '/locallife-admin-tests-' . bin2hex(random_bytes(8));
mkdir($runtime, 0700, true);
$processes = [];
$failures = [];
$passed = 0;

function assertThat(bool $condition, string $message): void {
    if (!$condition) { throw new RuntimeException($message); }
}
function copyTree(string $from, string $to): void {
    mkdir($to, 0700, true);
    foreach (new FilesystemIterator($from) as $item) {
        if ($item->isDir()) { copyTree($item->getPathname(), $to . '/' . $item->getFilename()); }
        else { copy($item->getPathname(), $to . '/' . $item->getFilename()); }
    }
}
function removeTree(string $path): void {
    // All cleanup is confined to this suite's randomly generated temporary directory.
    foreach (new FilesystemIterator($path) as $item) {
        if ($item->isDir()) { removeTree($item->getPathname()); }
        else { unlink($item->getPathname()); }
    }
    rmdir($path);
}
function unusedPort(): int {
    $socket=stream_socket_server('tcp://127.0.0.1:0',$error,$message);
    if ($socket===false) { throw new RuntimeException($message); }
    $name=stream_socket_get_name($socket,false); fclose($socket);
    return (int)substr($name,strrpos($name,':')+1);
}
function phpCommand(): array {
    $command=[PHP_BINARY,'-n'];
    $ext=ini_get('extension_dir');
    if (!str_starts_with($ext,'/') && !preg_match('/^[A-Za-z]:[\\\\\/]/',$ext)) { $ext=getcwd().'/'.$ext; }
    return [...$command,'-d','extension_dir='.$ext,'-d','extension=curl','-d','extension=mbstring','-d','extension=fileinfo','-d','display_errors=0','-d','log_errors=1','-d','date.timezone=Asia/Kuala_Lumpur'];
}
function launchServer(string $router, string $cwd, int $port, array $environment, string $log): mixed {
    $process=proc_open([...phpCommand(),'-S','127.0.0.1:'.$port,$router],[0=>['pipe','r'],1=>['file',$log,'a'],2=>['file',$log,'a']],$pipes,$cwd,$environment);
    if (!is_resource($process)) { throw new RuntimeException('Could not launch PHP server.'); }
    fclose($pipes[0]);
    for ($i=0;$i<100;$i++) {
        $socket=@stream_socket_client('tcp://127.0.0.1:'.$port,$error,$message,0.05);
        if ($socket) { fclose($socket); return $process; }
        if (!proc_get_status($process)['running']) { throw new RuntimeException('PHP server stopped: '.file_get_contents($log)); }
        usleep(50000);
    }
    throw new RuntimeException('PHP server did not start: '.file_get_contents($log));
}
function request(string $method, array $query, ?array $body=null, array $files=[], string $path='/'): array {
    global $appUrl,$cookieJar;
    $curl=curl_init($appUrl.$path.($query?'?'.http_build_query($query):'')); $headers=[];
    curl_setopt_array($curl,[CURLOPT_RETURNTRANSFER=>true,CURLOPT_CUSTOMREQUEST=>$method,CURLOPT_FOLLOWLOCATION=>false,CURLOPT_COOKIEFILE=>$cookieJar,CURLOPT_COOKIEJAR=>$cookieJar,CURLOPT_TIMEOUT=>10,
        CURLOPT_HEADERFUNCTION=>static function($curl,string $line) use (&$headers): int {
            if (str_contains($line,':')) { [$key,$value]=explode(':',$line,2); $headers[strtolower(trim($key))][]=trim($value); } return strlen($line);
        }]);
    if ($body!==null) { curl_setopt($curl,CURLOPT_POSTFIELDS,$files?$body+$files:http_build_query($body)); }
    $html=curl_exec($curl);
    if ($html===false) { throw new RuntimeException(curl_error($curl)); }
    $status=(int)curl_getinfo($curl,CURLINFO_RESPONSE_CODE); unset($curl);
    return ['status'=>$status,'body'=>$html,'headers'=>$headers];
}
function csrfToken(array $response): string {
    if (!preg_match('/name="csrf"\s+value="([a-f0-9]{64})"/',$response['body'],$match)) { throw new RuntimeException('Rendered form is missing its CSRF token.'); }
    return $match[1];
}
function expectStatus(array $response,int $status): void {
    assertThat($response['status']===$status,'Expected HTTP '.$status.', received '.$response['status'].'. '.strip_tags(substr($response['body'],0,350)));
}
function expectRedirect(array $response,string $page): void {
    expectStatus($response,303);
    assertThat(($response['headers']['location'][0]??null)==='/?page='.$page,'Expected redirect to '.$page.'.');
}
function logs(?string $path=null): array {
    global $runtime;
    $records=array_map(static fn(string $line): array=>json_decode($line,true,512,JSON_THROW_ON_ERROR),file($runtime.'/requests.jsonl',FILE_IGNORE_NEW_LINES) ?: []);
    return $path===null?$records:array_values(array_filter($records,static fn(array $record): bool=>$record['path']===$path));
}
function test(string $name,Closure $run): void {
    global $passed,$failures;
    try { $run(); $passed++; echo 'PASS '.$name."\n"; }
    catch (Throwable $error) { $failures[]=$name.': '.$error->getMessage(); echo 'FAIL '.end($failures)."\n"; }
}
function sessionFile(): string {
    global $runtime,$cookieJar;
    $lines=file($cookieJar,FILE_IGNORE_NEW_LINES) ?: [];
    $session=null;
    foreach ($lines as $line) {
        $parts=explode("\t",$line);
        if (count($parts)===7 && $parts[5]==='locallife_admin') { $session=$parts[6]; }
    }
    assertThat($session!==null && preg_match('/^[a-zA-Z0-9,-]+$/',$session)===1,'Session cookie not found.');
    return $runtime.'/site/var/sess_'.$session;
}
function updateSessionTimestamp(string $key,int $timestamp): void {
    $file=sessionFile();
    $content=file_get_contents($file);
    $pattern=$key==='expires_at'?'/"expires_at";i:\d+;/':'/'.preg_quote($key,'/').'\|i:\d+;/';
    $replacement=$key==='expires_at'?'"expires_at";i:'.$timestamp.';':$key.'|i:'.$timestamp.';';
    $updated=preg_replace($pattern,$replacement,$content,1,$count);
    assertThat($count===1,'Session timestamp '.$key.' was absent.');
    file_put_contents($file,$updated);
}

try {
    foreach (['src','public','views'] as $directory) {
        if (!is_dir($root.'/'.$directory)) { throw new RuntimeException('The admin '.$directory.' directory is not ready.'); }
        copyTree($root.'/'.$directory,$runtime.'/site/'.$directory);
    }
    $stubPort=unusedPort(); $appPort=unusedPort();
    $appUrl='http://127.0.0.1:'.$appPort; $cookieJar=$runtime.'/cookies.txt';
    $environment=getenv();
    $environment['APP_ENV']='test'; $environment['APP_URL']=$appUrl;
    $environment['SUPABASE_URL']='http://127.0.0.1:'.$stubPort;
    $environment['SUPABASE_PUBLISHABLE_KEY']='sb_publishable_test_contract';
    $environment['TEST_STATE_DIR']=$runtime;
    touch($runtime.'/requests.jsonl');
    $processes[]=launchServer(__DIR__.'/supabase_stub.php',__DIR__,$stubPort,$environment,$runtime.'/stub.log');
    $processes[]=launchServer($runtime.'/site/public/router.php',$runtime.'/site/public',$appPort,$environment,$runtime.'/app.log');

    $factor='10000000-0000-4000-8000-000000000001';
    $record='20000000-0000-4000-8000-000000000001';
    $version=str_repeat('a',32);
    $csrf='';
    $anonymousResponse=[];

    test('anonymous dashboard redirects to website login',function() use (&$anonymousResponse): void { $anonymousResponse=request('GET',['page'=>'dashboard']); expectRedirect($anonymousResponse,'login'); });
    test('login page supplies protected session and security headers',function() use (&$csrf,&$anonymousResponse): void {
        $response=request('GET',['page'=>'login']); expectStatus($response,200); $csrf=csrfToken($response);
        assertThat(($response['headers']['cache-control'][0]??'')==='no-store, private','Login must not be cached.');
        assertThat(str_contains($response['headers']['content-security-policy'][0]??'',"frame-ancestors 'none'"),'Missing frame protection.');
        $cookies=strtolower(implode(';',array_merge($anonymousResponse['headers']['set-cookie']??[],$response['headers']['set-cookie']??[])));
        assertThat(str_contains($cookies,'httponly'),'Session cookie is missing HttpOnly.');
        assertThat(str_contains($cookies,'samesite=lax'),'Session cookie is missing SameSite.');
    });
    test('missing CSRF is rejected before contacting Supabase',function(): void {
        $before=count(logs()); expectStatus(request('POST',['page'=>'login'],['action'=>'login','email'=>'admin@example.test','password'=>'test-password-only']),403);
        assertThat(count(logs())===$before,'Invalid CSRF reached Supabase.');
    });
    test('customer credentials cannot open the dedicated administrator website',function() use (&$csrf): void {
        $response=request('POST',['page'=>'login'],['csrf'=>$csrf,'action'=>'login','email'=>'customer@example.test','password'=>'test-password-only']); expectStatus($response,401);
        assertThat(str_contains($response['body'],'invited administrator'),'Login failed without a useful administrator-access message.');
        expectRedirect(request('GET',['page'=>'dashboard']),'login');
    });
    test('login authenticates but routes to authenticator gate',function() use (&$csrf): void {
        expectRedirect(request('POST',['page'=>'login'],['csrf'=>$csrf,'action'=>'login','email'=>'admin@example.test','password'=>'test-password-only']),'mfa');
        $response=request('GET',['page'=>'mfa']); expectStatus($response,200); $csrf=csrfToken($response);
        assertThat(!str_contains($response['body'],'fixture-access'),'Access token leaked into HTML.');
    });
    test('aal1 cannot read dashboard or perform administrator mutations',function() use (&$csrf,$record,$version): void {
        $analytics=count(logs('/rest/v1/rpc/admin_analytics')); $mutations=count(logs('/rest/v1/rpc/admin_mutate'));
        expectRedirect(request('GET',['page'=>'dashboard']),'mfa');
        expectRedirect(request('POST',['page'=>'users'],['csrf'=>$csrf,'action'=>'user_status','record_id'=>$record,'version'=>$version,'active'=>'false','reason'=>'Testing authenticator gate']),'mfa');
        assertThat(count(logs('/rest/v1/rpc/admin_analytics'))===$analytics,'Analytics fetched before MFA.');
        assertThat(count(logs('/rest/v1/rpc/admin_mutate'))===$mutations,'Mutation reached backend before MFA.');
    });
    test('wrong factor and malformed OTP cannot create a challenge',function() use (&$csrf,$factor): void {
        $before=count(logs('/auth/v1/factors/'.$factor.'/challenge'));
        expectStatus(request('POST',['page'=>'mfa'],['csrf'=>$csrf,'action'=>'verify','factor_id'=>'99999999-0000-4000-8000-000000000001','code'=>'123456']),403);
        expectStatus(request('POST',['page'=>'mfa'],['csrf'=>$csrf,'action'=>'verify','factor_id'=>$factor,'code'=>'12345']),400);
        assertThat(count(logs('/auth/v1/factors/'.$factor.'/challenge'))===$before,'Invalid factor/code created a challenge.');
    });
    test('valid OTP upgrades tokens and opens dashboard',function() use (&$csrf,$factor): void {
        expectRedirect(request('POST',['page'=>'mfa'],['csrf'=>$csrf,'action'=>'verify','factor_id'=>$factor,'code'=>'123456']),'dashboard');
        $response=request('GET',['page'=>'dashboard']); expectStatus($response,200); $csrf=csrfToken($response);
        $entries=logs('/rest/v1/rpc/admin_analytics');
        assertThat(end($entries)['token']==='fixture-access-aal2','Analytics did not use verified user access token.');
    });
    test('fresh password login clears stale MFA and recovery context',function() use (&$csrf,$factor): void {
        $fields=['enrollment'=>['id'=>'99999999-0000-4000-8000-000000000001'],'password_recovery'=>true,'pkce_verifier'=>'old-verifier','pkce_started'=>time(),'pkce_flow'=>'recovery'];
        $content=file_get_contents(sessionFile());
        foreach($fields as $key=>$value) { assertThat(!str_contains($content,$key.'|'),'Unexpected preexisting transient fixture '.$key); $content.=$key.'|'.serialize($value); }
        file_put_contents(sessionFile(),$content);
        expectRedirect(request('POST',['page'=>'login'],['csrf'=>$csrf,'action'=>'login','email'=>'admin@example.test','password'=>'test-password-only']),'mfa');
        $content=file_get_contents(sessionFile());
        foreach(array_keys($fields) as $key) { assertThat(!str_contains($content,$key.'|'),'Fresh login retained '.$key.'.'); }
        $csrf=csrfToken(request('GET',['page'=>'mfa']));
        expectRedirect(request('POST',['page'=>'mfa'],['csrf'=>$csrf,'action'=>'verify','factor_id'=>$factor,'code'=>'123456']),'dashboard');
        expectRedirect(request('GET',['page'=>'reset']),'dashboard');
        $csrf=csrfToken(request('GET',['page'=>'dashboard']));
    });
    test('all administrative modules render realistic nonempty records',function(): void {
        foreach (['users','providers','categories','bookings','reviews','disputes','refunds','analytics','audit'] as $page) {
            $response=request('GET',['page'=>$page]); expectStatus($response,200);
            assertThat(strlen($response['body'])>1000,'Empty page '.$page.'.');
            assertThat(!str_contains($response['body'],'Something went wrong'),'Render failed for '.$page.'.');
        }
    });
    test('record details render and carry concurrency versions',function() use ($record,$version): void {
        foreach (['users','providers','categories','bookings','reviews','disputes'] as $page) {
            $response=request('GET',['page'=>$page,'id'=>$record]); expectStatus($response,200);
            assertThat(str_contains($response['body'],$version),'Missing record version on '.$page.' detail.');
        }
    });
    test('provider working hours align day zero with Monday',function() use ($record): void {
        $response=request('GET',['page'=>'providers','id'=>$record]); expectStatus($response,200);
        assertThat(preg_match('~<dt>Monday</dt>\s*<dd>09:00–17:00</dd>~u',$response['body'])===1,'Day-zero working hours were assigned to the wrong weekday.');
    });
    test('expired verified credentials retain a safe revoke-verification form',function() use ($record,$version,$runtime): void {
        file_put_contents($runtime.'/fixture-state.json',json_encode(['expired_verified_certificate'=>true]));
        try {
            $response=request('GET',['page'=>'providers','id'=>$record]); expectStatus($response,200);
            preg_match_all('~<form\b[^>]*>[\s\S]*?</form>~i',$response['body'],$matches);
            $forms=array_values(array_filter($matches[0],static fn(string $form): bool=>str_contains($form,'name="action" value="certificate_verify"')));
            assertThat(count($forms)===1 && str_contains($forms[0],'Remove verification'),'An expired verified credential lost its revoke action.');
            $form=$forms[0];
            assertThat(str_contains($form,'name="verified" value="false"'),'Expired credential form attempted to grant verification.');
            assertThat(str_contains($form,'name="record_id" value="'.$record.'"') && str_contains($form,'name="version" value="'.$version.'"'),'Revoke form is missing its credential identity/version.');
            expectRedirect(request('POST',['page'=>'providers'],['csrf'=>csrfToken($response),'action'=>'certificate_verify','record_id'=>$record,'version'=>$version,'verified'=>'false','reason'=>'Credential expired and requires renewed evidence']),'providers');
            $entries=logs('/rest/v1/rpc/admin_mutate'); $entry=end($entries);
            assertThat($entry['token']==='fixture-access-aal2' && $entry['body']['action_name']==='certificate_verify' && $entry['body']['expected_version']===$version && $entry['body']['payload']['verified']==='false','Credential revocation did not preserve authenticated versioned mutation semantics.');
        } finally { file_put_contents($runtime.'/fixture-state.json','{}'); }
    });
    test('credential document uses a 60-second authenticated storage link',function() use ($record,$environment): void {
        $response=request('GET',['page'=>'document','id'=>$record]); expectStatus($response,303);
        assertThat(($response['headers']['location'][0]??'')===$environment['SUPABASE_URL'].'/storage/v1/object/sign/provider-documents/fake.pdf?token=fixture-signed-token','Document redirect does not use the trusted bucket.');
        $entries=logs('/storage/v1/object/sign/provider-documents/fake.pdf');
        assertThat(end($entries)['token']==='fixture-access-aal2','Document signing did not use verified access token.');
    });
    test('filter pagination is forwarded and stored HTML is escaped',function(): void {
        $response=request('GET',['page'=>'users','q'=>'<script>alert(1)</script>','status'=>'Active','p'=>2]); expectStatus($response,200);
        $entries=logs('/rest/v1/rpc/admin_list'); $request=end($entries);
        assertThat($request['body']===['resource'=>'users','search'=>'<script>alert(1)</script>','status_filter'=>'Active','page_number'=>2],'List filtering contract changed.');
        assertThat(!str_contains($response['body'],'<script>alert(1)</script>'),'Stored HTML is executable.');
        assertThat(str_contains($response['body'],'&lt;script&gt;alert(1)&lt;/script&gt;'),'Name/search value was not escaped.');
    });
    test('mutations use verified token and an explicit payload allowlist',function() use (&$csrf,$record,$version): void {
        expectRedirect(request('POST',['page'=>'users'],['csrf'=>$csrf,'action'=>'user_status','record_id'=>$record,'version'=>$version,'active'=>'false','reason'=>'Temporary suspension for investigation','role'=>'super_admin','unexpected'=>'secret']),'users');
        $entries=logs('/rest/v1/rpc/admin_mutate'); $entry=end($entries);
        assertThat($entry['body']['payload']===['active'=>'false','reason'=>'Temporary suspension for investigation'],'Untrusted fields escaped the mutation allowlist.');
        assertThat($entry['body']['expected_version']===$version,'Concurrency version was not forwarded.');
        assertThat($entry['token']==='fixture-access-aal2','Mutation did not use verified administrator token.');
    });
    test('new-category browser form forwards null identity and version',function() use (&$csrf): void {
        expectRedirect(request('POST',['page'=>'categories'],['csrf'=>$csrf,'action'=>'category_save','record_id'=>'','version'=>'','name'=>'Appliance repair','description'=>'Household appliance repair services','color'=>'#F97316','parent_id'=>'','display_order'=>'2','active'=>'true']),'categories');
        $entries=logs('/rest/v1/rpc/admin_mutate'); $entry=end($entries);
        assertThat($entry['body']['record_id']===null && $entry['body']['expected_version']===null,'New category should not have an existing identity/version.');
    });
    test('category icon upload validates content and generates a safe storage name',function() use (&$csrf,$record,$version,$runtime,$environment): void {
        $file=$runtime.'/icon.png'; file_put_contents($file,base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/ZioAAAAASUVORK5CYII='));
        $fields=['csrf'=>$csrf,'action'=>'category_save','record_id'=>$record,'version'=>$version,'name'=>'Plumbing','description'=>'Household plumbing','color'=>'#F97316','parent_id'=>'','display_order'=>'2','active'=>'true'];
        expectRedirect(request('POST',['page'=>'categories'],$fields,['icon_file'=>new CURLFile($file,'image/png','untrusted-name.php')]),'categories');
        $entries=logs('/rest/v1/rpc/admin_mutate'); $entry=end($entries);
        assertThat(preg_match('~^'.preg_quote($environment['SUPABASE_URL'],'~').'/storage/v1/object/public/category-icons/[a-f0-9]{32}\.png$~',$entry['body']['payload']['icon_url']??'')===1,'Uploaded image did not get a generated PNG name.');
        $uploads=array_values(array_filter(logs(),static fn(array $request): bool=>str_starts_with($request['path'],'/storage/v1/object/category-icons/') && $request['method']==='POST'));
        assertThat(count($uploads)===1 && $uploads[0]['content_type']==='image/png' && $uploads[0]['content_bytes']===filesize($file),'Upload content/type contract changed.');
        assertThat($uploads[0]['token']==='fixture-access-aal2','Upload did not use verified administrator access.');
    });
    test('failed category mutation removes its uploaded orphan icon',function() use (&$csrf,$record,$runtime): void {
        $response=request('POST',['page'=>'categories'],['csrf'=>$csrf,'action'=>'category_save','record_id'=>$record,'version'=>str_repeat('b',32),'name'=>'Plumbing','color'=>'#F97316','active'=>'true'],['icon_file'=>new CURLFile($runtime.'/icon.png','image/png','icon.png')]);
        expectStatus($response,409);
        $entries=logs('/storage/v1/object/category-icons'); $cleanup=end($entries);
        assertThat($cleanup['method']==='DELETE' && count($cleanup['body']['prefixes'])===1,'Orphan icon cleanup was not requested.');
    });
    test('unsupported category image is rejected before uploading',function() use (&$csrf,$record,$version,$runtime): void {
        $file=$runtime.'/icon.gif'; file_put_contents($file,base64_decode('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'));
        $before=count(logs());
        expectStatus(request('POST',['page'=>'categories'],['csrf'=>$csrf,'action'=>'category_save','record_id'=>$record,'version'=>$version,'name'=>'Plumbing'],['icon_file'=>new CURLFile($file,'image/png','image.png')]),400);
        $new=array_slice(logs(),$before);
        assertThat(count(array_filter($new,static fn(array $request): bool=>str_starts_with($request['path'],'/storage/v1/object/category-icons/')))===0,'Unsupported image reached storage.');
    });
    test('malformed image bytes return a controlled validation error',function() use (&$csrf,$record,$version,$runtime): void {
        $file=$runtime.'/truncated.png'; file_put_contents($file,"\x89PNG\r\n\x1a\n");
        expectStatus(request('POST',['page'=>'categories'],['csrf'=>$csrf,'action'=>'category_save','record_id'=>$record,'version'=>$version,'name'=>'Plumbing'],['icon_file'=>new CURLFile($file,'image/png','truncated.png')]),400);
    });
    test('invalid identifier, array version and array payload cannot reach mutation RPC',function() use (&$csrf,$record,$version): void {
        $before=count(logs('/rest/v1/rpc/admin_mutate'));
        $base=['csrf'=>$csrf,'action'=>'user_status','record_id'=>$record,'version'=>$version,'active'=>'false','reason'=>'Testing invalid request shapes'];
        expectStatus(request('POST',['page'=>'users'],array_replace($base,['record_id'=>'not-a-uuid'])),400);
        expectStatus(request('POST',['page'=>'users'],array_replace($base,['record_id'=>['x'=>'y']])),400);
        expectStatus(request('POST',['page'=>'users'],array_replace($base,['version'=>['x'=>'y']])),400);
        expectStatus(request('POST',['page'=>'users'],array_replace($base,['reason'=>['x'=>'y']])),400);
        assertThat(count(logs('/rest/v1/rpc/admin_mutate'))===$before,'Invalid request reached mutation RPC.');
    });
    test('GET cannot execute a mutation and unknown action fails',function() use (&$csrf): void {
        $before=count(logs('/rest/v1/rpc/admin_mutate'));
        expectStatus(request('GET',['page'=>'users','action'=>'user_status','active'=>'false']),200);
        expectStatus(request('POST',['page'=>'users'],['csrf'=>$csrf,'action'=>'unsafe_operation']),400);
        assertThat(count(logs('/rest/v1/rpc/admin_mutate'))===$before,'GET/unknown operation mutated data.');
    });
    test('optimistic concurrency conflict is shown without success redirect',function() use (&$csrf,$record): void {
        $response=request('POST',['page'=>'users'],['csrf'=>$csrf,'action'=>'user_status','record_id'=>$record,'version'=>str_repeat('b',32),'active'=>'false','reason'=>'Testing stale form submission']);
        expectStatus($response,409); assertThat(str_contains($response['body'],'This record changed'),'Backend conflict message was lost.');
    });
    test('invalid calendar date is rejected before analytics RPC',function(): void {
        $before=count(logs('/rest/v1/rpc/admin_analytics'));
        expectStatus(request('GET',['page'=>'analytics','from'=>'2026-02-31','to'=>'2026-10-01']),400);
        assertThat(count(logs('/rest/v1/rpc/admin_analytics'))===$before,'Invalid calendar date reached backend.');
    });
    test('analytics UUID, region and date filters reach the shared RPC contract',function() use ($record): void {
        $response=request('GET',['page'=>'analytics','from'=>'2026-10-01','to'=>'2026-10-01','category_id'=>$record,'region'=>'Selangor','provider_id'=>$record]); expectStatus($response,200);
        $entries=logs('/rest/v1/rpc/admin_analytics'); $entry=end($entries);
        assertThat($entry['body']===['date_from'=>'2026-10-01','date_to'=>'2026-10-01','category_filter'=>$record,'region_filter'=>'Selangor','provider_filter'=>$record],'Analytics filter contract was not forwarded.');
        assertThat(str_contains($response['body'],'name="category_id"') && str_contains($response['body'],'name="provider_id"') && str_contains($response['body'],'name="region"'),'Reporting filter controls are missing.');
    });
    test('invalid analytics identifiers fail before requesting data',function(): void {
        $before=count(logs('/rest/v1/rpc/admin_analytics'));
        expectStatus(request('GET',['page'=>'analytics','category_id'=>'not-a-uuid']),400);
        expectStatus(request('GET',['page'=>'analytics','provider_id'=>'not-a-uuid']),400);
        expectStatus(request('GET',['page'=>'analytics','region'=>['bad'=>'shape']]),400);
        assertThat(count(logs('/rest/v1/rpc/admin_analytics'))===$before,'Invalid analytics filter reached backend.');
    });
    test('analytics preserves controlled errors for reversed or overlong periods',function(): void {
        expectStatus(request('GET',['page'=>'analytics','from'=>'2026-10-02','to'=>'2026-10-01']),400);
        expectStatus(request('GET',['page'=>'analytics','from'=>'2025-01-01','to'=>'2026-10-01']),400);
    });
    test('zero new bookings still renders collections from older bookings',function() use ($runtime): void {
        file_put_contents($runtime.'/fixture-state.json',json_encode(['zero_bookings'=>true]));
        try {
            $response=request('GET',['page'=>'analytics']); expectStatus($response,200);
            assertThat(str_contains($response['body'],'Plumbing') && str_contains($response['body'],'75.00'),'Zero-booking period hid its category collections.');
            assertThat(!str_contains($response['body'],'Something went wrong'),'Zero-booking period failed to render.');
        } finally { file_put_contents($runtime.'/fixture-state.json','{}'); }
    });
    test('CSV preserves all pages and neutralizes spreadsheet formulas',function(): void {
        $response=request('GET',['page'=>'bookings','p'=>2,'export'=>1,'q'=>'Plumbing','status'=>'Pending']); expectStatus($response,200);
        assertThat(str_starts_with($response['headers']['content-type'][0]??'','text/csv'),'Export returned HTML.');
        $stream=fopen('php://memory','r+'); fwrite($stream,substr($response['body'],3)); rewind($stream); $rows=[];
        while(($row=fgetcsv($stream,0,',','"',''))!==false) { $rows[]=$row; } fclose($stream);
        assertThat(count($rows)===22,'Expected header + 21 rows, received '.count($rows).'.');
        $ids=array_column(array_slice($rows,1),0); assertThat(count(array_unique($ids))===21,'Export duplicated or omitted booking pages.');
        assertThat($rows[1][1][0]==="'" && $rows[1][2][0]==="'" && $rows[1][3][0]==="'",'Formula-like CSV cells are not neutralized.');
        $requests=logs('/rest/v1/rpc/admin_list');
        foreach(array_slice($requests,-2) as $entry) { assertThat(($entry['body']['search']??null)==='Plumbing' && ($entry['body']['status_filter']??null)==='Pending','Export lost list filters.'); }
    });
    test('analytics CSV includes category, daily revenue and filter metadata',function() use ($record): void {
        $response=request('GET',['page'=>'analytics','export'=>1,'from'=>'2026-10-01','to'=>'2026-10-01','category_id'=>$record,'region'=>'Selangor','provider_id'=>$record]); expectStatus($response,200);
        assertThat(str_contains($response['headers']['content-disposition'][0]??'','attachment'),'Analytics download headers missing.');
        assertThat(str_contains($response['body'],'gross_collected,1680.00'),'Analytics export omitted collected payments.');
        assertThat(str_contains($response['body'],'2026-10-01,2,1,160.00'),'Analytics export omitted daily revenue.');
        assertThat(str_contains($response['body'],'Plumbing,21,18,1680.00'),'Analytics export omitted category summary.');
        assertThat(str_contains($response['body'],'"Fixture Plumbing",21,18,4.8'),'Analytics export omitted provider performance.');
        assertThat(str_contains($response['body'],'category_id,'.$record) && str_contains($response['body'],'provider_id,'.$record) && str_contains($response['body'],'region,Selangor'),'Analytics CSV lost filter metadata.');
    });
    test('printable booking report includes every filtered page and escapes HTML',function() use ($runtime): void {
        file_put_contents($runtime.'/fixture-state.json',json_encode(['unsafe_booking_name'=>true]));
        try {
            $response=request('GET',['page'=>'bookings','p'=>2,'export'=>'print','q'=>'Plumbing','status'=>'Pending']); expectStatus($response,200);
            assertThat(str_starts_with($response['headers']['content-type'][0]??'text/html','text/html'),'Print report returned CSV.');
            assertThat(!isset($response['headers']['content-disposition']),'Print report should open in browser, not download CSV.');
            assertThat(str_contains($response['headers']['content-security-policy'][0]??'',"script-src 'self'"),'Print report lost its script policy.');
            $rows=preg_match_all('/<tr\b[^>]*>/i',$response['body']); assertThat($rows===22,'Print report should contain header + 21 rows, received '.$rows.'.');
            $count=preg_match_all('/30000000-0000-4000-8000-\d{12}/',$response['body'],$matches); assertThat($count>=21 && count(array_unique($matches[0]))===21,'Print report duplicated or omitted booking pages.');
            assertThat(!str_contains($response['body'],'<script>alert(1)</script>') && str_contains($response['body'],'&lt;script&gt;alert(1)&lt;/script&gt;'),'Print report did not escape customer HTML.');
            $entries=logs('/rest/v1/rpc/admin_list');
            foreach(array_slice($entries,-2) as $entry) { assertThat($entry['body']['search']==='Plumbing' && $entry['body']['status_filter']==='Pending','Print export lost filters.'); }
        } finally { file_put_contents($runtime.'/fixture-state.json','{}'); }
    });
    test('report stylesheet and print script are served with browser-safe MIME types',function(): void {
        $style=request('GET',[],null,[],'/assets/report.css'); expectStatus($style,200);
        assertThat(str_starts_with($style['headers']['content-type'][0]??'','text/css'),'Report stylesheet returned a routed HTML page.');
        assertThat(str_contains($style['body'],'@page') && str_contains($style['body'],'landscape'),'Print page layout is missing.');
        $script=request('GET',[],null,[],'/assets/admin.js'); expectStatus($script,200);
        assertThat(str_contains($script['headers']['content-type'][0]??'','javascript'),'Print script returned a routed HTML page.');
        assertThat(str_contains($script['body'],'data-print-report') && str_contains($script['body'],'window.print()'),'Print button is not connected to the browser print dialog.');
    });
    test('downstream export failure returns an error without a partial CSV attachment',function() use ($runtime): void {
        file_put_contents($runtime.'/fixture-state.json',json_encode(['fail_booking_page'=>2]));
        try {
            $response=request('GET',['page'=>'bookings','export'=>1]); expectStatus($response,503);
            assertThat(!isset($response['headers']['content-disposition']),'Failed export was sent as a downloadable attachment.');
            assertThat(!str_starts_with($response['body'],"\xEF\xBB\xBF"),'Failed export leaked a partial CSV.');
        } finally { file_put_contents($runtime.'/fixture-state.json','{}'); }
    });
    test('unknown routes and unsupported exports return controlled errors',function(): void {
        expectStatus(request('GET',['page'=>'does-not-exist']),404);
        expectStatus(request('GET',['page'=>'users','export'=>1]),400);
    });
    test('expired access token refresh preserves verified session',function(): void {
        updateSessionTimestamp('expires_at',time()-1);
        expectStatus(request('GET',['page'=>'dashboard']),200);
        $entries=logs('/auth/v1/token'); $refresh=end($entries);
        assertThat($refresh['query']['grant_type']==='refresh_token','Expired token was not refreshed.');
        assertThat($refresh['body']['refresh_token']==='fixture-refresh-aal2','Wrong refresh token used.');
    });
    test('idle session expires and signs out remotely',function(): void {
        updateSessionTimestamp('last_activity',time()-1801);
        $before=count(logs('/auth/v1/logout'));
        expectRedirect(request('GET',['page'=>'dashboard']),'login');
        assertThat(count(logs('/auth/v1/logout'))===$before+1,'Expired session did not revoke its remote session.');
    });
    test('password recovery uses PKCE, requires MFA and logs out after reset',function() use (&$csrf,$factor): void {
        $csrf=csrfToken(request('GET',['page'=>'forgot']));
        expectRedirect(request('POST',['page'=>'forgot'],['csrf'=>$csrf,'action'=>'recover','email'=>'admin@example.test']),'forgot');
        $entries=logs('/auth/v1/recover'); $recovery=end($entries);
        assertThat(($recovery['body']['code_challenge_method']??'')==='s256' && strlen($recovery['body']['code_challenge']??'')===43,'Recovery did not send S256 PKCE challenge.');
        expectRedirect(request('GET',['page'=>'callback','code'=>'fixture-recovery-code']),'mfa');
        $csrf=csrfToken(request('GET',['page'=>'mfa']));
        expectRedirect(request('POST',['page'=>'mfa'],['csrf'=>$csrf,'action'=>'verify','factor_id'=>$factor,'code'=>'123456']),'reset');
        $csrf=csrfToken(request('GET',['page'=>'reset']));
        expectRedirect(request('POST',['page'=>'reset'],['csrf'=>$csrf,'action'=>'reset','password'=>'new-test-password-only','confirm'=>'new-test-password-only']),'login');
        expectRedirect(request('GET',['page'=>'dashboard']),'login');
        $entries=logs('/auth/v1/user');
        assertThat(count(array_filter($entries,static fn(array $entry): bool=>$entry['method']==='PUT' && $entry['body']['password']==='new-test-password-only'))===1,'Password update was not sent exactly once.');
    });
    test('explicit logout clears verified session',function() use (&$csrf,$factor): void {
        $csrf=csrfToken(request('GET',['page'=>'login']));
        expectRedirect(request('POST',['page'=>'login'],['csrf'=>$csrf,'action'=>'login','email'=>'admin@example.test','password'=>'test-password-only']),'mfa');
        $csrf=csrfToken(request('GET',['page'=>'mfa']));
        expectRedirect(request('POST',['page'=>'mfa'],['csrf'=>$csrf,'action'=>'verify','factor_id'=>$factor,'code'=>'123456']),'dashboard');
        $csrf=csrfToken(request('GET',['page'=>'dashboard']));
        expectRedirect(request('POST',['page'=>'dashboard'],['csrf'=>$csrf,'action'=>'logout']),'login');
        expectRedirect(request('GET',['page'=>'dashboard']),'login');
    });
    test('account activation uses PKCE and does not grant password recovery',function() use (&$csrf,$factor): void {
        $csrf=csrfToken(request('GET',['page'=>'login']));
        expectRedirect(request('POST',['page'=>'login'],['csrf'=>$csrf,'action'=>'login','email'=>'admin@example.test','password'=>'test-password-only']),'mfa');
        $csrf=csrfToken(request('GET',['page'=>'mfa']));
        expectRedirect(request('POST',['page'=>'mfa'],['csrf'=>$csrf,'action'=>'verify','factor_id'=>$factor,'code'=>'123456']),'dashboard');
        $csrf=csrfToken(request('GET',['page'=>'signup']));
        expectStatus(request('POST',['page'=>'signup'],['csrf'=>$csrf,'action'=>'signup','email'=>'admin@example.test','password'=>'short','confirm'=>'short']),400);
        expectRedirect(request('POST',['page'=>'signup'],['csrf'=>$csrf,'action'=>'signup','email'=>'admin@example.test','password'=>'activation-test-password','confirm'=>'activation-test-password','role'=>'super_admin']),'signup');
        $entries=logs('/auth/v1/signup'); $activation=end($entries);
        assertThat(!isset($activation['body']['role']) && !isset($activation['body']['data']),'Client metadata attempted to grant an admin role.');
        assertThat($activation['body']['code_challenge_method']==='s256','Activation did not use PKCE.');
        expectRedirect(request('GET',['page'=>'dashboard']),'login');
        assertThat(!str_contains(file_get_contents(sessionFile()),'auth|'),'Confirmation-required signup retained a previous authenticated identity.');
        expectRedirect(request('GET',['page'=>'callback','code'=>'fixture-confirmation-code']),'mfa');
        $csrf=csrfToken(request('GET',['page'=>'mfa']));
        expectRedirect(request('POST',['page'=>'mfa'],['csrf'=>$csrf,'action'=>'verify','factor_id'=>$factor,'code'=>'123456']),'dashboard');
        expectRedirect(request('GET',['page'=>'reset']),'dashboard');
        $csrf=csrfToken(request('GET',['page'=>'dashboard']));
        expectRedirect(request('POST',['page'=>'dashboard'],['csrf'=>$csrf,'action'=>'logout']),'login');
    });
    test('first-time authenticator enrollment verifies before granting access',function() use (&$csrf,$factor,$runtime): void {
        file_put_contents($runtime.'/fixture-state.json',json_encode(['factor_unverified'=>true]));
        $csrf=csrfToken(request('GET',['page'=>'login']));
        expectRedirect(request('POST',['page'=>'login'],['csrf'=>$csrf,'action'=>'login','email'=>'admin@example.test','password'=>'test-password-only']),'mfa');
        $response=request('GET',['page'=>'mfa']); expectStatus($response,200); $csrf=csrfToken($response);
        assertThat(str_contains($response['body'],'Set up authenticator'),'New account did not offer enrollment.');
        expectRedirect(request('POST',['page'=>'mfa'],['csrf'=>$csrf,'action'=>'enroll']),'mfa');
        $response=request('GET',['page'=>'mfa']); expectStatus($response,200); $csrf=csrfToken($response);
        assertThat(str_contains($response['body'],'TEST-SETUP-SECRET') && str_contains($response['body'],'data:image/svg+xml;base64,'),'Enrollment setup secret/QR was not rendered safely.');
        expectRedirect(request('GET',['page'=>'dashboard']),'mfa');
        expectRedirect(request('POST',['page'=>'mfa'],['csrf'=>$csrf,'action'=>'verify','factor_id'=>$factor,'code'=>'123456']),'dashboard');
        $csrf=csrfToken(request('GET',['page'=>'dashboard']));
        expectRedirect(request('POST',['page'=>'dashboard'],['csrf'=>$csrf,'action'=>'logout']),'login');
    });
    test('unauthorized immediate activation clears returned authentication tokens',function() use (&$csrf,$runtime): void {
        file_put_contents($runtime.'/fixture-state.json',json_encode(['deny_activation'=>true,'signup_immediate_tokens'=>true]));
        try {
            $csrf=csrfToken(request('GET',['page'=>'signup']));
            expectStatus(request('POST',['page'=>'signup'],['csrf'=>$csrf,'action'=>'signup','email'=>'customer@example.test','password'=>'activation-test-password','confirm'=>'activation-test-password']),403);
            $session=file_get_contents(sessionFile());
            foreach(['auth','admin','enrollment','password_recovery'] as $key) { assertThat(!str_contains($session,$key.'|'),'Unauthorized activation retained '.$key.'.'); }
            expectRedirect(request('GET',['page'=>'dashboard']),'login');
        } finally { file_put_contents($runtime.'/fixture-state.json','{}'); }
    });
    test('unauthorized PKCE activation callback clears its saved user session',function() use (&$csrf,$runtime): void {
        file_put_contents($runtime.'/fixture-state.json',json_encode(['deny_activation'=>true]));
        try {
            $csrf=csrfToken(request('GET',['page'=>'signup']));
            expectRedirect(request('POST',['page'=>'signup'],['csrf'=>$csrf,'action'=>'signup','email'=>'customer@example.test','password'=>'activation-test-password','confirm'=>'activation-test-password']),'signup');
            expectStatus(request('GET',['page'=>'callback','code'=>'fixture-confirmation-code']),403);
            $session=file_get_contents(sessionFile());
            foreach(['auth','admin','enrollment','password_recovery'] as $key) { assertThat(!str_contains($session,$key.'|'),'Unauthorized callback retained '.$key.'.'); }
            expectRedirect(request('GET',['page'=>'dashboard']),'login');
        } finally { file_put_contents($runtime.'/fixture-state.json','{}'); }
    });

    test('configuration rejects service credentials and unsafe deployment URLs',function() use ($runtime): void {
        $keys=['APP_ENV','APP_URL','SUPABASE_URL','SUPABASE_PUBLISHABLE_KEY']; $saved=[];
        foreach ($keys as $key) { $saved[$key]=getenv($key); }
        try {
            $base=['APP_ENV'=>'development','APP_URL'=>'http://127.0.0.1:8080','SUPABASE_URL'=>'https://fixture.supabase.co','SUPABASE_PUBLISHABLE_KEY'=>'sb_publishable_test_contract'];
            $serviceRole='e30.'.rtrim(strtr(base64_encode(json_encode(['role'=>'service_role'])), '+/','-_'),'=').'.fixture';
            foreach ([['SUPABASE_PUBLISHABLE_KEY'=>'sb_secret_never_use'],['SUPABASE_PUBLISHABLE_KEY'=>$serviceRole],['SUPABASE_URL'=>'http://fixture.supabase.co'],['SUPABASE_URL'=>'https://fixture.supabase.co.evil.example'],['APP_ENV'=>'production','APP_URL'=>'http://example.test']] as $case) {
                foreach (array_replace($base,$case) as $key=>$value) { putenv($key.'='.$value); }
                $rejected=false;
                try { new LocalLife\Config($runtime.'/config'); } catch (RuntimeException) { $rejected=true; }
                assertThat($rejected,'Unsafe configuration was accepted: '.json_encode(array_keys($case)));
            }
            $anon='e30.'.rtrim(strtr(base64_encode(json_encode(['role'=>'anon'])), '+/','-_'),'=').'.fixture';
            foreach (array_replace($base,['SUPABASE_PUBLISHABLE_KEY'=>$anon]) as $key=>$value) { putenv($key.'='.$value); }
            assertThat((new LocalLife\Config($runtime.'/config'))->key===$anon,'Legacy anon key should be accepted.');
        } finally { foreach ($saved as $key=>$value) { putenv($value===false?$key:$key.'='.$value); } }
    });

    $appLog=file_get_contents($runtime.'/app.log');
    test('all requests complete without PHP warnings or fatals',function() use ($appLog): void {
        assertThat(preg_match('/PHP (?:Warning|Fatal error|Deprecated|Notice)|Admin error [a-f0-9]+ /',$appLog)!==1,'PHP emitted a warning/fatal: '.$appLog);
    });
} catch (Throwable $error) {
    $failures[]='Suite setup: '.$error->getMessage(); echo 'FAIL '.end($failures)."\n";
} finally {
    foreach (array_reverse($processes) as $process) { if (is_resource($process)) { proc_terminate($process); proc_close($process); } }
    if ($failures && is_file($runtime.'/app.log')) { fwrite(STDERR,"Application log retained at ".$runtime."/app.log\n"); }
    if (!$failures) { removeTree($runtime); }
}
echo "\n".$passed.' passed, '.count($failures)." failed.\n";
exit($failures ? 1 : 0);
