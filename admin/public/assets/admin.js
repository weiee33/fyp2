'use strict';

document.querySelectorAll('[data-print-report]').forEach((button) => {
    button.addEventListener('click', () => window.print());
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

document.querySelectorAll('form[method="post"]').forEach((form) => {
    let confirmed = false;
    form.addEventListener('submit', (event) => {
        if (form.dataset.submitting === 'true') {
            event.preventDefault();
            return;
        }
        if (form.dataset.confirm && !confirmed) {
            event.preventDefault();
            if (confirmDialog.open) return;
            confirmDialog.querySelector('#confirm-message').textContent = form.dataset.confirm;
            confirmDialog.returnValue = 'cancel';
            const submitter = event.submitter;
            confirmDialog.addEventListener('close', () => {
                if (confirmDialog.returnValue === 'confirm') {
                    confirmed = true;
                    form.requestSubmit(submitter || undefined);
                    confirmed = false;
                } else {
                    submitter?.focus();
                }
            }, { once: true });
            confirmDialog.showModal();
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
