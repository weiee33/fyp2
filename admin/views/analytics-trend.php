<?php
declare(strict_types=1);
// Only the authorized, applied reporting result is sent to the chart. Zoom and
// inspection are local views of this result; neither changes export filters.
$chartSeries = $chartKind === 'revenue'
    ? [['key'=>'gross_collected','label'=>'Gross collected','color'=>'#ea580c','money'=>true],['key'=>'refunded','label'=>'Confirmed refunds','color'=>'#dc2626','money'=>true]]
    : [['key'=>'bookings','label'=>'Bookings','color'=>'#ea580c','money'=>false],
       ['key'=>'users','label'=>'New users · global','color'=>'#5979a3','money'=>false]];
$chartRows = array_map(static fn(array $day): array => [
    'date'=>(string)$day['date'], 'bookings'=>(int)$day['bookings'],
    'refunded'=>(float)($day['refunded'] ?? 0), 'users'=>(int)$day['users'], 'gross_collected'=>(float)($day['gross_collected'] ?? 0),
], $daily);
?>
<div class="market-chart" data-market-chart data-rows="<?= e(json_encode($chartRows, JSON_THROW_ON_ERROR)) ?>" data-series="<?= e(json_encode($chartSeries, JSON_THROW_ON_ERROR)) ?>" data-title="<?= $chartKind === 'revenue' ? 'Gross collection trend' : 'Community activity' ?>">
    <div class="market-toolbar" hidden>
        <div class="market-periods" role="group" aria-label="Visible chart period">
            <?php foreach(['all'=>'All','7'=>'7D','30'=>'30D','90'=>'90D'] as $days=>$label): ?>
            <button type="button" data-window="<?= e((string)$days) ?>" aria-pressed="<?= $days==='all'?'true':'false' ?>"><?= e($label) ?></button>
            <?php endforeach; ?>
        </div>
        <div class="market-tools" role="group" aria-label="Chart controls">
            <button type="button" data-zoom="in" aria-label="Zoom in" title="Zoom in">+</button>
            <button type="button" data-zoom="out" aria-label="Zoom out" title="Zoom out">−</button>
            <button type="button" data-reset>Reset</button>
        </div>
    </div>
    <div class="market-readout" hidden>
        <div class="market-date"><span data-point-date></span><span data-point-state>Latest day</span></div>
        <div class="market-values">
            <?php foreach($chartSeries as $series): ?>
            <button type="button" class="market-series" data-series-key="<?= e($series['key']) ?>" aria-pressed="true" aria-label="Show <?= e($series['label']) ?>">
                <span class="market-series-name"><?= e($series['label']) ?></span>
                <strong data-value>—</strong><span class="market-change" data-change></span>
            </button>
            <?php endforeach; ?>
        </div>
    </div>
    <div class="market-stage" hidden>
        <svg class="market-plot" role="slider" tabindex="0" aria-label="Inspect <?= $chartKind==='revenue'?'gross collections':'community activity' ?> by date" aria-orientation="horizontal" aria-valuemin="0" aria-valuemax="<?= max(0,count($daily)-1) ?>" aria-valuenow="0" aria-describedby="<?= e($chartKind) ?>-chart-help"></svg>
    </div>
    <div class="market-navigator" hidden><span data-visible-from></span><input type="range" min="0" max="0" value="0" aria-label="Move visible date window"><span data-visible-to></span></div>
    <p class="market-help" id="<?= e($chartKind) ?>-chart-help" hidden>Hover or drag to inspect · Click to pin · Arrow keys to move · Esc to release</p>
    <p class="market-fallback">Exact daily values are available in the table below.</p>
    <span class="sr-only" role="status" data-chart-announcement></span>
</div>
