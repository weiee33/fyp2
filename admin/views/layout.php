<?php
declare(strict_types=1);
function viewIcon(string $name, string $class = ''): string {
    $paths = [
        'grid'=>'<rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/>',
        'users'=>'<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2m20 0v-2a4 4 0 0 0-3-3.87M16 3a4 4 0 0 1 0 8"/><circle cx="9" cy="7" r="4"/>',
        'shield'=>'<path d="m12 3 8 3v6c0 5-8 9-8 9s-8-4-8-9V6l8-3Z"/><path d="m8 12 3 3 5-6"/>',
        'layers'=>'<path d="m12 3 10 6-10 6L2 9l10-6Zm-10 12 10 6 10-6M2 12l10 6 10-6"/>',
        'calendar'=>'<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M16 3v4M8 3v4M3 11h18m-13 5h3"/>',
        'star'=>'<path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2-5.6-3-5.6 3 1.1-6.2L3 9.6l6.2-.9L12 3Z"/>',
        'alert'=>'<path d="m12 3 10 18H2L12 3Zm0 6v5m0 3h.01"/>',
        'wallet'=>'<path d="M20 8V5a2 2 0 0 0-2-2H5a3 3 0 0 0 0 6h15v11H5a3 3 0 0 1-3-3V6m18 7h-6v4h6m-3-2h.01"/>',
        'chart'=>'<path d="M3 3v18h18M7 16v-5m5 5V7m5 9v-9"/>',
        'history'=>'<path d="M3 11a9 9 0 1 1 2.7 7M3 4v7h7m2-4v5l3 2"/>',
        'arrow'=>'<path d="M5 12h14m-6-6 6 6-6 6"/>',
        'search'=>'<circle cx="10" cy="10" r="6"/><path d="m15 15 6 6"/>',
        'download'=>'<path d="M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5"/>',
        'logout'=>'<path d="M9 21H3V3h6m5 5 5 4-5 4m-7-4h12"/>',
        'menu'=>'<path d="M3 6h18M3 12h18M3 18h18"/>',
        'plus'=>'<path d="M12 5v14M5 12h14"/>',
        'check'=>'<path d="m5 12 4 4L19 6"/>',
        'lock'=>'<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3m-4 4v3"/>',
        'eye'=>'<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>',
        'clock'=>'<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    ];
    return '<svg class="icon '.e($class).'" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'.($paths[$name] ?? $paths['grid']).'</svg>';
}
function viewFields(string $action, ?string $id = null, ?string $version = null): string {
    return csrf().'<input type="hidden" name="action" value="'.e($action).'"><input type="hidden" name="record_id" value="'.e($id).'"><input type="hidden" name="version" value="'.e($version).'">';
}
function viewReason(string $id, string $label = 'Reason for this action'): void { ?>
    <label for="<?= e($id) ?>"><?= e($label) ?> <span class="required">*</span></label>
    <textarea id="<?= e($id) ?>" name="reason" required minlength="10" maxlength="1000" rows="3" placeholder="Explain the decision so the team and affected user can understand it."></textarea>
    <p class="field-note">10–1,000 characters. Recorded in the audit trail.</p>
<?php }
function viewPair(string $label, mixed $value): void { ?><div class="detail-pair"><dt><?= e($label) ?></dt><dd><?= e($value ?? '—') ?></dd></div><?php }
function viewSafeLink(mixed $value, string $label = 'Open document'): void {
    $link = (string)($value ?? '');
    if (filter_var($link, FILTER_VALIDATE_URL) && strtolower((string)parse_url($link, PHP_URL_SCHEME)) === 'https') { ?><a class="text-link" href="<?= e($link) ?>" target="_blank" rel="noopener noreferrer"><?= e($label) ?> ↗</a><?php }
    elseif ($link !== '') { ?><span class="muted">Document stored privately</span><?php }
    else { ?><span class="muted">No document supplied</span><?php }
}
$authPage = in_array($page, ['login','signup','forgot','reset','callback','mfa'], true);
$navigation = ['dashboard'=>['Overview','grid'],'users'=>['Users','users'],'providers'=>['Providers','shield'],'categories'=>['Service categories','layers'],'bookings'=>['Bookings & orders','calendar'],'reviews'=>['Reviews','star'],'disputes'=>['Disputes','alert'],'refunds'=>['Refund requests','wallet'],'analytics'=>['Analytics & reports','chart'],'audit'=>['Audit trail','history']];
if (($admin['role_level'] ?? '') !== 'super_admin') { unset($navigation['audit']); }
$descriptions = ['dashboard'=>'A clear view of your service community.','users'=>'Manage customer and provider access with an accountable record of every decision.','providers'=>'Review provider credentials and help customers book with confidence.','categories'=>'Keep your service catalogue organised and easy to discover.','bookings'=>'Follow each service from request to completion.','reviews'=>'Protect useful, fair feedback across your community.','disputes'=>'Review service issues and document clear resolutions.','refunds'=>'Track refund requests and their payment processing status.','analytics'=>'Understand demand, performance and collected payments.','audit'=>'Review the actions taken by your administrative team.'];
?>
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><title><?= e($titles[$page] ?? 'Administration') ?> · Local Life</title><link rel="stylesheet" href="/assets/admin.css"><script src="/assets/admin.js" defer></script></head>
<body class="<?= $authPage ? 'auth-page' : 'app-page' ?>">
<a class="skip-link" href="#main">Skip to content</a>
<?php if ($authPage): ?>
    <main id="main" class="auth-shell">
        <section class="auth-story" aria-label="Local Life administration">
            <a class="brand brand-light" href="<?= e(url('login')) ?>"><span class="brand-mark"><?= viewIcon('layers') ?></span><span>Local Life<span class="brand-sub">ADMINISTRATION</span></span></a>
            <div class="auth-story-copy"><span class="eyebrow">BETTER SERVICES. STRONGER COMMUNITIES.</span><h1>Good service<br>starts with<br>great care.</h1><p>The space to support your providers, look after your customers and keep everyday life moving.</p><div class="auth-story-note"><?= viewIcon('shield') ?><span>Secure access for your admin team</span></div></div>
            <div class="auth-art" aria-hidden="true"><div class="art-ring ring-one"></div><div class="art-ring ring-two"></div><div class="art-ring ring-three"></div><span class="art-card art-house">⌂</span><span class="art-card art-check"><?= viewIcon('check') ?></span></div>
            <p class="auth-footer">Local Life Service Assistant · Malaysia</p>
        </section>
        <section class="auth-content"><div class="auth-card">
            <div class="mobile-brand brand"><span class="brand-mark"><?= viewIcon('layers') ?></span><span>Local Life</span></div>
            <?php if ($flash): ?><div class="notice notice-success" role="status"><?= viewIcon('check') ?><span><?= e($flash) ?></span></div><?php endif; ?>
            <?php if ($error): ?><div class="notice notice-error" role="alert"><?= viewIcon('alert') ?><span><?= e($error) ?></span></div><?php endif; ?>
            <?php require __DIR__.'/auth.php'; ?>
        </div><p class="auth-security"><?= viewIcon('lock') ?> Your session is protected with two-step verification.</p></section>
    </main>
<?php else: ?>
    <aside id="sidebar" class="sidebar" aria-label="Primary navigation">
        <a class="brand" href="<?= e(url('dashboard')) ?>"><span class="brand-mark"><?= viewIcon('layers') ?></span><span>Local Life<span class="brand-sub">ADMINISTRATION</span></span></a>
        <p class="nav-label">WORKSPACE</p><nav>
        <?php foreach ($navigation as $route=>$item): ?>
            <?php if ($route==='reviews'): ?><p class="nav-label">TRUST & SUPPORT</p><?php elseif($route==='analytics'): ?><p class="nav-label">INSIGHTS</p><?php endif; ?>
            <a class="nav-link <?= $page===$route?'active':'' ?>" href="<?= e(url($route)) ?>" <?= $page===$route?'aria-current="page"':'' ?>><?= viewIcon($item[1]) ?><span><?= e($item[0]) ?></span></a>
        <?php endforeach; ?></nav>
        <div class="sidebar-bottom"><div class="admin-avatar"><?= e(strtoupper(mb_substr($admin['full_name'] ?? 'A',0,1))) ?></div><div class="admin-person"><strong><?= e($admin['full_name'] ?? 'Administrator') ?></strong><span><?= ($admin['role_level'] ?? '')==='super_admin'?'Super Admin':'Staff Admin' ?></span></div><form method="post" action="<?= e(url($page)) ?>"><?= viewFields('logout') ?><button class="icon-button" title="Sign out" aria-label="Sign out"><?= viewIcon('logout') ?></button></form></div>
    </aside>
    <div class="workspace"><header class="topbar"><div class="topbar-leading"><button type="button" class="icon-button nav-toggle" data-toggle-nav aria-controls="sidebar" aria-expanded="false" aria-label="Open navigation"><?= viewIcon('menu') ?></button><span class="breadcrumb">Workspace <span>/</span> <strong><?= e($titles[$page]) ?></strong></span></div><div class="topbar-meta"><span class="secure-pill"><?= viewIcon('shield') ?> Secure session</span><span class="topbar-date"><?= e(date('d M Y')) ?></span></div></header>
    <main id="main" class="main-content"><div class="page-heading"><div><span class="eyebrow">LOCAL LIFE ADMIN</span><h1><?= e($titles[$page]) ?></h1><p><?= e($descriptions[$page] ?? '') ?></p></div><?php if($page==='categories'): ?><a class="button button-primary" href="<?= e(url('categories',['new'=>'1'])) ?>"><?= viewIcon('plus') ?> Add category</a><?php elseif($page==='analytics'): ?><a class="button button-secondary" href="<?= e(url('analytics',['from'=>$_GET['from'] ?? date('Y-m-01'),'to'=>$_GET['to'] ?? date('Y-m-d'),'category_id'=>$_GET['category_id'] ?? '','region'=>$_GET['region'] ?? '','provider_id'=>$_GET['provider_id'] ?? '','export'=>'1'])) ?>"><?= viewIcon('download') ?> Export CSV</a><?php endif; ?></div>
    <?php if ($flash): ?><div class="notice notice-success" role="status"><?= viewIcon('check') ?><span><?= e($flash) ?></span></div><?php endif; ?>
    <?php if ($error): ?><div class="notice notice-error" role="alert"><?= viewIcon('alert') ?><span><?= e($error) ?></span></div><?php endif; ?>
    <?php if (!$error || $data): ?><?php require __DIR__.(in_array($page,['dashboard','analytics'],true)?'/analytics.php':'/resources.php'); ?><?php endif; ?>
    <footer class="workspace-footer"><span>Local Life Service Assistant</span><span>All times shown in Malaysia time (MYT).</span></footer>
    </main></div>
<?php endif; ?>
</body></html>
