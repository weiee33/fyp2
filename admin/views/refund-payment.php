<?php declare(strict_types=1);
$payment=$record['payment'] ?? null;
$refunds=$payment['refunds'] ?? [];
$pending=array_filter($refunds,static fn(array $r):bool=>in_array($r['status'],['Requested','Processing'],true));
$remaining=(float)($payment['remaining'] ?? 0);
?>
<section class="section-divider"><h3>Payment &amp; refunds</h3>
<?php if(!$payment): ?><p class="muted">No payment recorded.</p><?php else: ?>
<dl class="detail-list"><?php viewPair('Payment status',$payment['payment_status']);viewPair('Collected',money($payment['payment_amount']));viewPair('Available to refund',money($remaining));viewPair('Payment reference',$payment['fpx_transaction_ref']); ?></dl>
<?php if($refunds): ?><ol class="timeline"><?php foreach($refunds as $refund): ?><li><?= badge($refund['status']) ?> <strong><?= e(money($refund['amount'])) ?></strong><time><?= e(localDate($refund['updated_at'])) ?></time><a class="text-link" href="<?= e(url('refunds',['id'=>$refund['refund_id']])) ?>">Open refund →</a></li><?php endforeach; ?></ol><?php endif; ?>
<?php if($pending): ?><div class="info-card">A refund is pending. Open it to process or refresh its status.</div>
<?php elseif(!isset($payment['remaining'])): ?><div class="info-card">Refund details are unavailable. Reload this record before continuing.</div>
<?php elseif($payment['payment_status']==='Refunded' || $remaining<=0): ?><div class="info-card">This payment has been fully refunded.</div>
<?php elseif(($admin['role_level'] ?? '')==='super_admin' && $payment['payment_status']==='Success'): ?>
<form class="stack-form" method="post" action="<?= e($detailAction) ?>">
<?= viewFields('refund_request',$payment['payment_id'],$payment['version']) ?>
<div><label for="refund-amount">Refund amount (MYR)</label><input id="refund-amount" name="amount" type="number" min="0.01" max="<?= e(number_format($remaining,2,'.','')) ?>" step="0.01" value="<?= e(number_format($remaining,2,'.','')) ?>" required></div>
<?php viewReason('refund-reason','Reason for refund'); ?>
<p class="field-note">Next, review and submit this request to Stripe. A partial refund leaves the remaining paid amount available; a full confirmed refund cancels an unfinished booking.</p>
<button class="button button-primary">Review refund request</button></form>
<?php endif; endif; ?></section>
