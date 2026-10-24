'use strict';

const chartDialog = document.getElementById('chart-detail');
let chartOpener;
document.querySelectorAll('[data-chart-detail]').forEach((point) => {
    const open = () => {
        if (!chartDialog) return;
        chartOpener = point;
        document.getElementById('chart-detail-title').textContent = point.dataset.chartTitle;
        const values = document.getElementById('chart-detail-values');
        values.replaceChildren();
        Object.entries(JSON.parse(point.dataset.chartDetail)).forEach(([label, value]) => {
            const term = document.createElement('dt'), detail = document.createElement('dd');
            term.textContent = label; detail.textContent = String(value);
            values.append(term, detail);
        });
        chartDialog.showModal();
    };
    point.addEventListener('click', open);
    point.addEventListener('keydown', (event) => {
        if (point.tagName.toLowerCase() !== 'button' && (event.key === 'Enter' || event.key === ' ')) { event.preventDefault(); open(); }
    });
});
chartDialog?.querySelector('[data-close-chart]').addEventListener('click', () => chartDialog.close());
chartDialog?.addEventListener('close', () => chartOpener?.focus());

document.querySelectorAll('[data-print-report]').forEach((button) => {
    button.addEventListener('click', () => window.print());
});
// Navigate with GET even when the current document followed a rejected POST.
document.querySelector('[data-refresh]')?.addEventListener('click', () => window.location.assign(window.location.href));

const pinNavigation = document.querySelector('[data-pin-nav]');
const setPinned = (pinned) => {
    document.body.classList.toggle('nav-pinned', pinned);
    pinNavigation?.setAttribute('aria-pressed', String(pinned));
    pinNavigation?.setAttribute('aria-label', pinned ? 'Unpin sidebar' : 'Pin sidebar');
    pinNavigation?.setAttribute('title', pinned ? 'Unpin sidebar' : 'Pin sidebar');
    const hint = document.querySelector('.sidebar-hint');
    if (hint) hint.textContent = pinned ? 'Navigation pinned' : 'Pin navigation';
};
try { setPinned(localStorage.getItem('homeserve.nav-pinned') === 'true'); } catch { /* Storage is optional. */ }
pinNavigation?.addEventListener('click', () => {
    const pinned = !document.body.classList.contains('nav-pinned');
    setPinned(pinned);
    try { localStorage.setItem('homeserve.nav-pinned', String(pinned)); } catch { /* Keep this page usable. */ }
});

document.querySelectorAll('[data-password]').forEach((button) => {
    button.addEventListener('click', () => {
        const input = document.getElementById(button.dataset.password);
        if (!input) return;
        const visible = input.type === 'password';
        input.type = visible ? 'text' : 'password';
        button.setAttribute('aria-label', visible ? 'Hide password' : 'Show password');
        button.setAttribute('aria-pressed', String(visible));
    });
});

const navButton = document.querySelector('[data-toggle-nav]');
const sidebar = document.getElementById('sidebar');
const desktopNavigation = window.matchMedia('(min-width: 761px)');
const updateNavigation = () => {
    if (sidebar) sidebar.inert = !desktopNavigation.matches && !document.body.classList.contains('nav-open');
};
const closeNavigation = () => {
    document.body.classList.remove('nav-open');
    if (navButton) {
        navButton.setAttribute('aria-expanded', 'false');
        navButton.setAttribute('aria-label', 'Open navigation');
    }
    updateNavigation();
};
if (navButton && sidebar) {
    updateNavigation();
    navButton.addEventListener('click', () => {
        const opened = document.body.classList.toggle('nav-open');
        navButton.setAttribute('aria-expanded', String(opened));
        navButton.setAttribute('aria-label', opened ? 'Close navigation' : 'Open navigation');
        updateNavigation();
        if (opened) sidebar.querySelector('a')?.focus();
    });
    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape' && document.body.classList.contains('nav-open')) {
            closeNavigation();
            navButton.focus();
        }
    });
    document.addEventListener('click', (event) => {
        if (!document.body.classList.contains('nav-open')) return;
        if (!sidebar.contains(event.target) && !navButton.contains(event.target)) closeNavigation();
    });
    desktopNavigation.addEventListener('change', () => {
        if (!desktopNavigation.matches && sidebar.contains(document.activeElement)) navButton.focus();
        closeNavigation();
    });
}

const confirmDialog = document.createElement('dialog');
confirmDialog.className = 'confirm-dialog';
confirmDialog.setAttribute('aria-labelledby', 'confirm-title');
confirmDialog.setAttribute('aria-describedby', 'confirm-message');
confirmDialog.innerHTML = '<form method="dialog"><h2 id="confirm-title">Confirm action</h2><p id="confirm-message"></p><div class="form-actions"><button class="button button-secondary" value="cancel" autofocus>Cancel</button><button class="button button-primary" value="confirm">Confirm</button></div></form>';
document.body.append(confirmDialog);

function askConfirmation(message, title = 'Confirm action', label = 'Confirm') {
    if (confirmDialog.open) return Promise.resolve(false);
    confirmDialog.querySelector('#confirm-title').textContent = title;
    confirmDialog.querySelector('#confirm-message').textContent = message;
    confirmDialog.querySelector('[value="confirm"]').textContent = label;
    confirmDialog.returnValue = 'cancel';
    return new Promise((resolve) => {
        confirmDialog.addEventListener('close', () => resolve(confirmDialog.returnValue === 'confirm'), { once: true });
        confirmDialog.showModal();
    });
}

document.querySelectorAll('form[method="post"]').forEach((form) => {
    let confirmed = false;
    form.addEventListener('submit', async (event) => {
        if (form.dataset.submitting === 'true') {
            event.preventDefault();
            return;
        }
        if (form.dataset.confirm && !confirmed) {
            event.preventDefault();
            const submitter = event.submitter;
            if (await askConfirmation(form.dataset.confirm)) {
                confirmed = true;
                form.requestSubmit(submitter || undefined);
                confirmed = false;
            } else { submitter?.focus(); }
            return;
        }
        const password = form.querySelector('[name="password"]');
        const confirmation = form.querySelector('[name="confirm"]');
        if (password && confirmation && password.value !== confirmation.value) {
            event.preventDefault();
            confirmation.setCustomValidity('The passwords must match.');
            confirmation.reportValidity();
            confirmation.addEventListener('input', () => confirmation.setCustomValidity(''), { once: true });
            return;
        }
        form.dataset.submitting = 'true';
        const submitter = event.submitter;
        if (submitter) {
            submitter.disabled = true;
            submitter.setAttribute('aria-busy', 'true');
        }
    });
});

const recordDialog = document.querySelector('[data-record-dialog]');
let recordDirty = false;
if (recordDialog) {
    const recovery = JSON.parse(recordDialog.dataset.recovery || '{}');
    const recoveryForm = Array.from(recordDialog.querySelectorAll('form[method="post"]')).find((form) =>
        form.elements.namedItem('action')?.value === recovery.action &&
        form.elements.namedItem('record_id')?.value === recovery.recordId);
    if (recoveryForm) {
        for (const [name, value] of Object.entries(recovery.values || {})) {
            const input = recoveryForm.elements.namedItem(name);
            if (input && !['hidden', 'file'].includes(input.type)) input.value = value;
        }
        recordDirty = true;
    } else if (recovery.values && Object.keys(recovery.values).length) {
        // A concurrent update may remove the action (for example, a closed support request).
        // Keep the draft readable without recreating an action the server no longer permits.
        const draft = document.createElement('details');
        draft.className = 'recovery-draft';
        const summary = document.createElement('summary');
        summary.textContent = 'Previous input · this action is no longer available';
        draft.append(summary);
        for (const [name, value] of Object.entries(recovery.values)) {
            if (!value) continue;
            const label = document.createElement('strong');
            label.textContent = name.replaceAll('_', ' ');
            const content = document.createElement('p');
            content.className = 'preserve-text';
            content.textContent = value;
            draft.append(label, content);
        }
        recordDialog.querySelector('.record-error')?.after(draft);
    }
    recordDialog.addEventListener('input', () => { recordDirty = true; });
    recordDialog.addEventListener('change', () => { recordDirty = true; });
    const sections = recordDialog.querySelector('[data-record-sections]');
    recordDialog.querySelectorAll('.detail-content h3').forEach((heading, index) => {
        heading.id = `record-section-${index}`;
        heading.tabIndex = -1;
        const button = document.createElement('button');
        button.type = 'button';
        button.textContent = heading.textContent;
        button.addEventListener('click', () => { heading.scrollIntoView({ block: 'start' }); heading.focus({ preventScroll: true }); });
        sections.append(button);
    });
    const closeRecord = async () => {
        if (recordDialog.querySelector('form[data-submitting="true"]')) return;
        if (recordDirty && !await askConfirmation('Your unsaved changes will be discarded.', 'Discard changes?', 'Discard')) return;
        recordDirty = false;
        recordDialog.close();
        document.body.classList.remove('record-open');
        document.querySelectorAll('.selected-row').forEach((row) => row.classList.remove('selected-row'));
        const closeLink = recordDialog.querySelector('[data-close-record]');
        history.replaceState(null, '', closeLink.href);
        const origin = document.querySelector(`[data-record-link="${CSS.escape(recordDialog.dataset.recordId)}"]`);
        (origin || document.getElementById('records-title'))?.focus({ preventScroll: true });
    };
    recordDialog.querySelectorAll('[data-close-record]').forEach((link) => link.addEventListener('click', (event) => {
        event.preventDefault(); closeRecord();
    }));
    recordDialog.addEventListener('cancel', (event) => { event.preventDefault(); closeRecord(); });
    // The server-rendered open state is a usable no-JavaScript fallback.
    recordDialog.close();
    recordDialog.showModal();
    document.body.classList.add('record-open');
    (recordDialog.querySelector('.record-error') || recordDialog.querySelector('#detail-title')).focus();
    window.addEventListener('beforeunload', (event) => {
        if (recordDirty && !recordDialog.querySelector('form[data-submitting="true"]')) {
            event.preventDefault(); event.returnValue = '';
        }
    });
}

const pageSwitcher = document.querySelector('[data-page-switcher]');
if (pageSwitcher) {
    const search = pageSwitcher.querySelector('input');
    const links = Array.from(pageSwitcher.querySelectorAll('.switcher-link'));
    const filterPages = () => {
        const query = search.value.trim().toLocaleLowerCase();
        links.forEach((link) => { link.hidden = !link.textContent.toLocaleLowerCase().includes(query); });
        pageSwitcher.querySelector('[data-no-pages]').hidden = links.some((link) => !link.hidden);
    };
    const openSwitcher = () => {
        if (document.querySelector('dialog[open]')) return;
        search.value = ''; filterPages(); pageSwitcher.showModal(); search.focus();
    };
    document.querySelector('[data-open-switcher]')?.addEventListener('click', openSwitcher);
    pageSwitcher.querySelector('[data-close-switcher]').addEventListener('click', () => pageSwitcher.close());
    search.addEventListener('input', filterPages);
    search.addEventListener('keydown', (event) => {
        const first = links.find((link) => !link.hidden);
        if (event.key === 'ArrowDown' && first) { event.preventDefault(); first.focus(); }
        if (event.key === 'Enter' && first) { event.preventDefault(); first.click(); }
    });
    document.addEventListener('keydown', (event) => {
        if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') { event.preventDefault(); openSwitcher(); }
    });
}

document.querySelectorAll('[data-copy]').forEach((button) => {
    button.addEventListener('click', async () => {
        const input = document.getElementById(button.dataset.copy);
        const status = document.getElementById('copy-status');
        if (!input || !status) return;
        try {
            await navigator.clipboard.writeText(input.value);
            status.textContent = 'Activation link copied.';
        } catch {
            input.focus();
            input.select();
            status.textContent = 'Select and copy the activation link above.';
        }
    });
});

window.addEventListener('pageshow', () => {
    document.querySelectorAll('form[data-submitting="true"]').forEach((form) => {
        delete form.dataset.submitting;
        form.querySelectorAll('[aria-busy="true"]').forEach((button) => {
            button.disabled = false;
            button.removeAttribute('aria-busy');
        });
    });
});
