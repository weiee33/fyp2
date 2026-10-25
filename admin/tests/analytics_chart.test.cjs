const { test } = require('node:test');
const assert = require('node:assert/strict');
const { ChartWindow, change } = require('../public/assets/analytics-chart.js');

test('inspection snaps to the nearest real day and clamps outside the plot', () => {
    const chart = new ChartWindow(31);
    assert.equal(chart.indexAt(-1), 0);
    assert.equal(chart.indexAt(0.5), 15);
    assert.equal(chart.indexAt(2), 30);
    chart.select(99);
    assert.equal(chart.selected, 30);
});
test('zoom keeps an inspected day in view and panning cannot escape applied data', () => {
    const chart = new ChartWindow(366);
    chart.select(180);
    chart.resize(7);
    assert.ok(chart.start <= 180 && chart.end >= 180);
    chart.move(999);
    assert.equal(chart.end, 365);
    assert.ok(chart.selected >= chart.start);
    chart.move(-99);
    assert.equal(chart.start, 0);
    chart.resize(1000);
    assert.equal(chart.start, 0);
    assert.equal(chart.end, 365);
});
test('empty, single and two-day windows have no division by zero or fake dates', () => {
    for (const length of [0, 1, 2]) {
        const chart = new ChartWindow(length);
        chart.resize(1);
        chart.move(100);
        assert.equal(chart.start, 0);
        assert.equal(chart.size, length);
        assert.ok(Number.isFinite(chart.indexAt(0.5)));
    }
});
test('repeated zoom, pan and inspection preserve window invariants', () => {
    const chart = new ChartWindow(367);
    for (let step = 0; step < 100; step++) {
        chart.resize((step * 17) % 400);
        chart.move(step * 19 - 300);
        chart.select(step * 31 - 500);
        assert.ok(chart.start >= 0 && chart.end < 367);
        assert.ok(chart.selected >= chart.start && chart.selected <= chart.end);
    }
});
test('daily changes distinguish zero baseline and unavailable previous day', () => {
    assert.equal(change(42, null), 'No previous day');
    assert.equal(change(0, 0), 'No change vs previous day');
    assert.equal(change(42, 0), 'Up from 0 vs previous day');
    assert.equal(change(0, 42), '-100.0% vs previous day');
    assert.equal(change(150, 100), '+50.0% vs previous day');
});
