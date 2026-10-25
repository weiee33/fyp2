'use strict';

// Daily reporting data has no OHLC prices: retain true daily lines and borrow
// trading-chart inspection, crosshairs and viewport controls without inventing data.
(() => {
    const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
    class ChartWindow {
        constructor(length) {
            this.length = length;
            this.start = 0;
            this.size = length;
            this.selected = Math.max(0, length - 1);
        }
        get end() { return this.start + this.size - 1; }
        resize(size, anchor = this.selected) {
            if (!this.length) return;
            const fraction = this.size > 1 ? (anchor - this.start) / (this.size - 1) : 0.5;
            this.size = clamp(Math.round(size), Math.min(3, this.length), this.length);
            this.start = clamp(Math.round(anchor - fraction * (this.size - 1)), 0, this.length - this.size);
            this.select(this.selected);
        }
        move(start) {
            this.start = clamp(Math.round(start), 0, this.length - this.size);
            this.select(this.selected);
        }
        select(index) { this.selected = clamp(Math.round(index), this.start, Math.max(this.start, this.end)); }
        indexAt(fraction) { return this.start + Math.round(clamp(fraction, 0, 1) * Math.max(0, this.size - 1)); }
    }
    const change = (current, previous) => previous === null ? 'No previous day'
        : previous === 0 ? (current === 0 ? 'No change vs previous day' : 'Up from 0 vs previous day')
        : `${current >= previous ? '+' : ''}${((current - previous) / previous * 100).toFixed(1)}% vs previous day`;
    if (typeof module !== 'undefined' && module.exports) module.exports = { ChartWindow, change };
    if (typeof document === 'undefined') return;

    const ns = 'http://www.w3.org/2000/svg';
    const svgNode = (tag, attributes, content) => {
        const element = document.createElementNS(ns, tag);
        Object.entries(attributes).forEach(([name, value]) => element.setAttribute(name, String(value)));
        if (content !== undefined) element.textContent = content;
        return element;
    };
    const dateLabel = (date, full = true) => new Intl.DateTimeFormat('en-MY', {
        day: '2-digit', month: 'short', ...(full ? { year: 'numeric' } : {}), timeZone: 'UTC',
    }).format(new Date(`${date}T00:00:00Z`));
    const number = new Intl.NumberFormat('en-MY', { maximumFractionDigits: 0 });
    const currency = new Intl.NumberFormat('en-MY', { style: 'currency', currency: 'MYR' });

    document.querySelectorAll('[data-market-chart]').forEach((root, chartIndex) => {
        const rows = JSON.parse(root.dataset.rows), series = JSON.parse(root.dataset.series);
        if (!rows.length) return;
        const model = new ChartWindow(rows.length);
        const plot = root.querySelector('.market-plot');
        const navigator = root.querySelector('input[type="range"]');
        const visible = new Set(series.map(s => s.key));
        const seriesButtons = Array.from(root.querySelectorAll('[data-series-key]'));
        let pinned = false, inspecting = false, drag = null, width = 700, height = 280;
        let left = 12, right = 600, top = 16, bottom = 240, yMax = 4, overlay;
        const format = (value, spec) => spec.money ? currency.format(value) : number.format(value);
        const x = index => model.size > 1 ? left + (index - model.start) / (model.size - 1) * (right - left) : (left + right) / 2;
        const y = value => bottom - value / yMax * (bottom - top);
        const readout = (announce = false) => {
            const row = rows[model.selected];
            root.querySelector('[data-point-date]').textContent = dateLabel(row.date);
            root.querySelector('[data-point-state]').textContent = pinned ? 'Pinned' : inspecting ? 'Inspecting' : 'Latest visible day';
            series.forEach((spec, i) => {
                seriesButtons[i].querySelector('[data-value]').textContent = format(row[spec.key], spec);
                seriesButtons[i].querySelector('[data-change]').textContent = change(row[spec.key], rows[model.selected - 1]?.[spec.key] ?? null);
            });
            const spoken = `${dateLabel(row.date)}. ${series.filter(s => visible.has(s.key)).map(s => `${s.label}: ${format(row[s.key], s)}`).join('. ')}`;
            plot.setAttribute('aria-valuenow', String(model.selected));
            plot.setAttribute('aria-valuetext', spoken);
            if (announce) root.querySelector('[data-chart-announcement]').textContent = spoken;
            overlay.replaceChildren();
            if (!inspecting && !pinned) return;
            const active = series.filter(s => visible.has(s.key));
            const primary = active[0];
            const px = x(model.selected), py = y(row[primary.key]);
            overlay.append(svgNode('line', { x1: px, x2: px, y1: top, y2: bottom, class: 'market-crosshair' }),
                svgNode('line', { x1: left, x2: right, y1: py, y2: py, class: 'market-crosshair' }));
            active.forEach(spec => overlay.append(svgNode('circle', { cx: px, cy: y(row[spec.key]), r: 4.5, fill: spec.color, stroke: '#fff', 'stroke-width': 2 })));
            const labelX = clamp(px, 48, right - 48);
            overlay.append(svgNode('rect', { x: labelX - 42, y: bottom + 7, width: 84, height: 24, rx: 4, class: 'market-axis-badge' }),
                svgNode('text', { x: labelX, y: bottom + 23, 'text-anchor': 'middle', class: 'market-badge-label' }, dateLabel(row.date, false)));
        };
        const draw = () => {
            if (!pinned && !inspecting) model.select(model.end);
            width = Math.max(260, root.querySelector('.market-stage').clientWidth);
            height = width < 460 ? 245 : 280;
            const active = series.filter(s => visible.has(s.key));
            const max = Math.max(0, ...rows.slice(model.start, model.end + 1).flatMap(row => active.map(s => row[s.key])));
            const step = max > 0 ? Math.pow(10, Math.floor(Math.log10(max / 4))) : 1;
            yMax = max > 0 ? Math.ceil(max / (step * 4)) * step * 4 : 4;
            if (!active[0].money) yMax = Math.max(4, Math.ceil(yMax / 4) * 4);
            // Reserve enough space for large monetary axis labels at any width.
            const labelLength = format(yMax, active[0]).length;
            right = width - Math.max(58, labelLength * 7 + 14);
            bottom = height - 38;
            plot.setAttribute('viewBox', `0 0 ${width} ${height}`);
            plot.setAttribute('aria-valuemin', String(model.start));
            plot.setAttribute('aria-valuemax', String(model.end));
            plot.replaceChildren();
            const defs = svgNode('defs', {});
            const gradient = svgNode('linearGradient', { id: `market-fill-${chartIndex}`, x1: 0, y1: 0, x2: 0, y2: 1 });
            gradient.append(svgNode('stop', { offset: '0%', 'stop-color': active[0].color, 'stop-opacity': '.16' }),
                svgNode('stop', { offset: '100%', 'stop-color': active[0].color, 'stop-opacity': '.01' }));
            defs.append(gradient); plot.append(defs);
            for (let tick = 0; tick <= 4; tick++) {
                const value = yMax * tick / 4, py = y(value);
                plot.append(svgNode('line', { x1: left, x2: right, y1: py, y2: py, class: 'market-grid' }),
                    svgNode('text', { x: right + 10, y: py + 4, class: 'market-axis' }, format(value, active[0])));
            }
            const labelCount = width < 420 ? 2 : 4;
            const indices = new Set(Array.from({ length: labelCount }, (_, i) => model.start + Math.round(i / (labelCount - 1) * (model.size - 1))));
            indices.forEach(index => plot.append(svgNode('text', { x: x(index), y: bottom + 23, 'text-anchor': index === model.start && model.size > 1 ? 'start' : index === model.end && model.size > 1 ? 'end' : 'middle', class: 'market-axis' }, dateLabel(rows[index].date, false))));
            active.forEach((spec, i) => {
                const points = rows.slice(model.start, model.end + 1).map((row, j) => `${x(model.start + j)},${y(row[spec.key])}`).join(' ');
                if (i === 0 && model.size > 1) plot.append(svgNode('polygon', { points: `${x(model.start)},${bottom} ${points} ${x(model.end)},${bottom}`, fill: `url(#market-fill-${chartIndex})` }));
                plot.append(svgNode('polyline', { points, fill: 'none', stroke: spec.color, 'stroke-width': 2.25, 'stroke-linejoin': 'round', 'stroke-linecap': 'round' }));
                if (model.size === 1) plot.append(svgNode('circle', { cx: x(model.start), cy: y(rows[model.start][spec.key]), r: 4, fill: spec.color }));
            });
            overlay = svgNode('g', { 'aria-hidden': 'true', 'pointer-events': 'none' }); plot.append(overlay);
            navigator.max = String(rows.length - model.size); navigator.value = String(model.start);
            navigator.disabled = model.size === rows.length;
            navigator.setAttribute('aria-valuetext', `${dateLabel(rows[model.start].date)} to ${dateLabel(rows[model.end].date)}`);
            root.querySelector('[data-visible-from]').textContent = dateLabel(rows[model.start].date, false);
            root.querySelector('[data-visible-to]').textContent = dateLabel(rows[model.end].date, false);
            root.querySelector('[data-zoom="in"]').disabled = model.size <= Math.min(3, rows.length);
            root.querySelector('[data-zoom="out"]').disabled = model.size === rows.length;
            seriesButtons.forEach(button => {
                button.disabled = visible.size === 1 && visible.has(button.dataset.seriesKey);
            });
            root.querySelectorAll('[data-window]').forEach(button => {
                const size = button.dataset.window === 'all' ? rows.length : Math.min(rows.length, Number(button.dataset.window));
                button.disabled = button.dataset.window !== 'all' && Number(button.dataset.window) >= rows.length;
                button.setAttribute('aria-pressed', String(model.size === size && (button.dataset.window === 'all' || size < rows.length)));
            });
            readout();
        };
        const inspect = event => {
            const rect = plot.getBoundingClientRect();
            model.select(model.indexAt(((event.clientX - rect.left) * width / rect.width - left) / (right - left)));
            inspecting = true; readout();
        };
        plot.addEventListener('pointermove', event => {
            if (drag && event.pointerId === drag.id) {
                drag.moved ||= Math.abs(event.clientX - drag.x) > 4;
                inspect(event);
            } else if (!pinned && event.pointerType !== 'touch') inspect(event);
        });
        plot.addEventListener('pointerdown', event => {
            if (event.button !== 0 || drag) return;
            drag = { id: event.pointerId, x: event.clientX, moved: false, wasPinned: pinned, index: model.selected };
            plot.setPointerCapture(event.pointerId); plot.focus({ preventScroll: true }); inspect(event);
        });
        plot.addEventListener('pointerup', event => {
            if (!drag || drag.id !== event.pointerId) return;
            pinned = drag.moved || !drag.wasPinned || drag.index !== model.selected;
            drag = null; plot.releasePointerCapture(event.pointerId); readout(true);
        });
        plot.addEventListener('pointercancel', () => { drag = null; });
        plot.addEventListener('pointerleave', () => {
            if (pinned || drag) return;
            inspecting = false; model.select(model.end); readout();
        });
        plot.addEventListener('keydown', event => {
            const offsets = { ArrowLeft: -1, ArrowRight: 1, PageUp: 7, PageDown: -7 };
            if (event.key in offsets || ['Home', 'End', 'Escape', 'Enter', ' '].includes(event.key)) {
                event.preventDefault();
                if (event.key === 'Escape') { pinned = false; inspecting = false; model.select(model.end); }
                else if (event.key === 'Enter' || event.key === ' ') { pinned = !pinned; inspecting = true; }
                else { model.select(event.key === 'Home' ? model.start : event.key === 'End' ? model.end : model.selected + offsets[event.key]); inspecting = true; }
                readout(true);
            }
        });
        root.querySelectorAll('[data-window]').forEach(button => button.addEventListener('click', () => {
            const size = button.dataset.window === 'all' ? rows.length : Number(button.dataset.window);
            model.resize(size); model.move(rows.length - model.size); model.select(model.end);
            pinned = false; inspecting = false; draw();
        }));
        root.querySelectorAll('[data-zoom]').forEach(button => button.addEventListener('click', () => {
            model.resize(button.dataset.zoom === 'in' ? model.size / 2 : model.size * 2); draw();
        }));
        root.querySelector('[data-reset]').addEventListener('click', () => {
            model.resize(rows.length); model.select(model.end); pinned = false; inspecting = false;
            series.forEach((spec, i) => { visible.add(spec.key); seriesButtons[i].setAttribute('aria-pressed', 'true'); }); draw();
        });
        navigator.addEventListener('input', () => { model.move(Number(navigator.value)); if (!pinned) model.select(model.end); draw(); });
        seriesButtons.forEach(button => button.addEventListener('click', () => {
            const key = button.dataset.seriesKey;
            if (visible.has(key) && visible.size === 1) return;
            if (visible.has(key)) visible.delete(key); else visible.add(key);
            button.setAttribute('aria-pressed', String(visible.has(key))); draw();
        }));
        root.querySelectorAll('[hidden]').forEach(element => element.hidden = false);
        root.querySelector('.market-fallback').hidden = true;
        draw();
        new ResizeObserver(draw).observe(root.querySelector('.market-stage'));
    });
})();
