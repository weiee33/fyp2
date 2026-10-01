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
const closeNavigation = () => {
    document.body.classList.remove('nav-open');
    if (navButton) {
        navButton.setAttribute('aria-expanded', 'false');
        navButton.setAttribute('aria-label', 'Open navigation');
    }
};
if (navButton) {
    navButton.addEventListener('click', () => {
        const opened = document.body.classList.toggle('nav-open');
        navButton.setAttribute('aria-expanded', String(opened));
        navButton.setAttribute('aria-label', opened ? 'Close navigation' : 'Open navigation');
    });
    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape' && document.body.classList.contains('nav-open')) {
            closeNavigation();
            navButton.focus();
        }
    });
    document.addEventListener('click', (event) => {
        if (!document.body.classList.contains('nav-open')) return;
        const sidebar = document.getElementById('sidebar');
        if (!sidebar.contains(event.target) && !navButton.contains(event.target)) closeNavigation();
    });
    window.matchMedia('(min-width: 761px)').addEventListener('change', (event) => {
        if (event.matches) closeNavigation();
    });
}

document.querySelectorAll('form[method="post"]').forEach((form) => {
    form.addEventListener('submit', (event) => {
        if (form.dataset.submitting === 'true') {
            event.preventDefault();
            return;
        }
        if (form.dataset.confirm && !window.confirm(form.dataset.confirm)) {
            event.preventDefault();
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

window.addEventListener('pageshow', () => {
    document.querySelectorAll('form[data-submitting="true"]').forEach((form) => {
        delete form.dataset.submitting;
        form.querySelectorAll('[aria-busy="true"]').forEach((button) => {
            button.disabled = false;
            button.removeAttribute('aria-busy');
        });
    });
});
