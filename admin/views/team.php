<?php declare(strict_types=1);
$activationLink=$config->appUrl.url('signup');
$items=$data['items'] ?? []; $total=(int)($data['total'] ?? 0); $currentPage=(int)($data['page'] ?? 1); $pageCount=max(1,(int)ceil($total/20));
$localLink=in_array(strtolower((string)parse_url($config->appUrl,PHP_URL_HOST)),['127.0.0.1','localhost','::1'],true);
$enteredEmail=is_string($_POST['email'] ?? '')?($_POST['email'] ?? ''):'';
?>
<div class="team-grid">
<section class="panel" aria-labelledby="invite-title"><div class="panel-heading"><div><h2 id="invite-title">Invite an administrator</h2><p>Use a separate admin email.</p></div></div>
<form method="post" action="<?= e(url('team')) ?>" class="stack-form team-form" data-confirm="Create this invitation with the selected role? Share the activation link only with the intended colleague.">
<?= viewFields('invitation_create') ?>
<div><label for="invite-email">Email address</label><input id="invite-email" name="email" type="email" autocomplete="off" required maxlength="254" placeholder="colleague@example.com" value="<?= e(($_POST['action'] ?? '')==='invitation_create'?$enteredEmail:'') ?>"></div>
<div><label for="invite-role">Admin role</label><select id="invite-role" name="role_level"><option value="staff">Staff Admin</option><option value="super_admin" <?= ($_POST['role_level'] ?? '')==='super_admin'?'selected':'' ?>>Super Admin</option></select><p class="field-note">Super Admins also manage invitations, audit history and refund requests.</p></div>
<p class="field-note">Expires in 7 days · email verification and MFA required. No invitation email is sent.</p>
<button class="button button-primary" type="submit"><?= viewIcon('plus') ?> Create invitation</button></form></section>
<section class="panel" aria-labelledby="activation-title"><div class="panel-heading"><h2 id="activation-title">Share the activation link</h2></div><div class="team-form">
<details class="inline-guide"><summary>How activation works</summary><ol class="activation-steps"><li>Create an invitation for your colleague's email.</li><li>Share this link and ask them to activate using that exact email.</li><li>They verify their email code, then set up an authenticator.</li></ol></details>
<label for="activation-link">Activation link</label><div class="copy-field"><input id="activation-link" type="text" readonly value="<?= e($activationLink) ?>"><button type="button" class="button button-secondary" data-copy="activation-link">Copy link</button></div><p class="field-note" id="copy-status" role="status" aria-live="polite"></p>
<?php if($localLink): ?><div class="notice notice-warning">Local link: colleagues on other devices need your deployed HTTPS admin address.</div><?php endif; ?>
<p class="field-note">Only invited, verified emails can activate. Revoking an invitation does not suspend an activated account.</p>
</div></section></div>
<?php if($data): ?>
<section class="panel resource-panel" aria-labelledby="invitations-title"><div class="panel-heading"><h2 id="invitations-title">Invitations <span class="count-tag"><?= number_format($total) ?></span></h2></div>
<form method="get" action="/" class="filter-bar"><input type="hidden" name="page" value="team"><div class="search-field"><?= viewIcon('search') ?><label class="sr-only" for="team-search">Search invitations by email</label><input id="team-search" type="search" name="q" maxlength="100" value="<?= e($_GET['q'] ?? '') ?>" placeholder="Search by email"></div><button class="button button-secondary" type="submit">Search</button><?php if(!empty($_GET['q'])): ?><a class="text-link" href="<?= e(url('team')) ?>">Clear</a><?php endif; ?></form>
<?php if(!$items): ?><div class="empty-state"><h3>No invitations found</h3><p>Create an invitation above or try another email search.</p></div><?php else: ?>
<div class="table-wrap"><table><thead><tr><th scope="col">Email & role</th><th scope="col">Status</th><th scope="col">Created</th><th scope="col">Expiry / accepted</th><th scope="col">Actions</th></tr></thead><tbody>
<?php foreach($items as $item): ?><tr><td><strong class="email-text"><?= e($item['email']) ?></strong><span class="cell-sub"><?= $item['role_level']==='super_admin'?'Super Admin':'Staff Admin' ?></span></td><td><?= badge($item['status']) ?></td><td><?= e(localDate($item['created_at'])) ?><span class="cell-sub"><?= e($item['invited_by_name'] ?? 'Initial setup') ?></span></td><td><?= e(localDate($item['status']==='Accepted'?$item['accepted_at']:$item['expires_at'])) ?></td><td>
<?php if($item['status']!=='Accepted'): ?><div class="invitation-actions">
<?php foreach(($item['status']==='Revoked'?['renew']:['renew','revoke']) as $operation): ?>
<form method="post" action="<?= e(url('team')) ?>" data-confirm="<?= e(($operation==='revoke'?'Revoke':'Renew for 7 days'). ' the invitation for '.$item['email'].'?') ?>"><?= viewFields('invitation_'.$operation,null,$item['version']) ?><input type="hidden" name="email" value="<?= e($item['email']) ?>"><input type="hidden" name="role_level" value="<?= e($item['role_level']) ?>"><button class="button button-small <?= $operation==='revoke'?'button-danger':'button-secondary' ?>"><?= $operation==='revoke'?'Revoke':'Renew' ?></button></form>
<?php endforeach; ?></div><?php else: ?><span class="muted">Activated</span><?php endif; ?></td></tr><?php endforeach; ?>
</tbody></table></div><?php endif; ?>
<div class="pagination"><p><?= number_format($total) ?> <?= $total===1?'invitation':'invitations' ?></p><div><span>Page <?= $currentPage ?> of <?= $pageCount ?></span><?php if($currentPage>1): ?><a class="button button-secondary button-small" href="<?= e(url('team',['p'=>$currentPage-1,'q'=>$_GET['q'] ?? ''])) ?>">Previous</a><?php endif; ?><?php if($currentPage<$pageCount): ?><a class="button button-secondary button-small" href="<?= e(url('team',['p'=>$currentPage+1,'q'=>$_GET['q'] ?? ''])) ?>">Next</a><?php endif; ?></div></div></section>
<?php endif; ?>
