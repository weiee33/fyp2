<?php declare(strict_types=1); ?>
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Local Life · Booking report</title><link rel="stylesheet" href="/assets/report.css"><script src="/assets/admin.js" defer></script></head>
<body>
<div class="report-controls"><a href="<?= e(url('bookings',['q'=>$_GET['q'] ?? '','status'=>$_GET['status'] ?? ''])) ?>">Back to bookings</a><button type="button" data-print-report>Print / Save PDF</button><p>Choose “Save as PDF” in your browser’s print dialog. A4 landscape layout is prepared for this report.</p></div>
<main><header><p class="brand">Local Life · Administration</p><h1>Booking report</h1><p>Generated <?= e(date('d M Y, H:i')) ?> MYT by <?= e($admin['full_name'] ?? 'Administrator') ?> · <?= number_format(count($reportItems)) ?> records</p><p>Status: <?= e(($_GET['status'] ?? '') ?: 'All') ?> · Search: <?= e(($_GET['q'] ?? '') ?: 'All') ?></p></header>
<table><thead><tr><th>Booking</th><th>Customer</th><th>Provider</th><th>Service</th><th>Scheduled (MYT)</th><th>Booking / Payment</th><th>Amount (MYR)</th></tr></thead><tbody>
<?php foreach($reportItems as $item): ?><tr><td class="record-id"><?= e($item['booking_id']) ?></td><td><?= e($item['customer_name']) ?></td><td><?= e($item['provider_name']) ?></td><td><?= e($item['service_name']) ?></td><td><?= e(localDate($item['scheduled_datetime'])) ?></td><td><?= e($item['booking_status']) ?><br><span><?= e($item['payment_status'] ?? 'Not recorded') ?></span></td><td class="amount"><?= e(number_format((float)$item['total_amount'],2)) ?></td></tr><?php endforeach; ?>
<?php if(!$reportItems): ?><tr><td colspan="7">No bookings match these filters.</td></tr><?php endif; ?>
</tbody></table><footer>Amounts represent booking totals. Payment status is shown separately; this report does not confirm a payout or refund.</footer></main>
</body></html>
