/*
 * Light/dark theme handling.
 * Loaded synchronously in <head> before the stylesheet so the initial theme is
 * applied before first paint. Without a manual choice the site follows the
 * system preference; a manual choice is persisted in localStorage when
 * available (storage failures fall back to an in-memory choice).
 */
(function () {
    'use strict';

    var STORAGE_KEY = 'jp-theme';
    var root = document.documentElement;
    var media = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;

    function readStored() {
        try {
            var value = window.localStorage.getItem(STORAGE_KEY);
            return value === 'dark' || value === 'light' ? value : null;
        } catch (e) {
            return null;
        }
    }

    function writeStored(value) {
        try {
            window.localStorage.setItem(STORAGE_KEY, value);
        } catch (e) {
            /* Storage unavailable: keep the in-memory choice only. */
        }
    }

    var manual = readStored();

    function systemTheme() {
        return media && media.matches ? 'dark' : 'light';
    }

    function currentTheme() {
        return manual || systemTheme();
    }

    function syncButton(theme) {
        var button = document.getElementById('theme-toggle');
        if (!button) return;
        var dark = theme === 'dark';
        button.setAttribute('aria-pressed', dark ? 'true' : 'false');
        button.title = dark ? 'Switch to light mode' : 'Switch to dark mode';
    }

    function apply(theme) {
        root.setAttribute('data-theme', theme);
        syncButton(theme);
    }

    apply(currentTheme());

    function onSystemChange() {
        if (!manual) apply(systemTheme());
    }

    if (media) {
        if (media.addEventListener) {
            media.addEventListener('change', onSystemChange);
        } else if (media.addListener) {
            media.addListener(onSystemChange);
        }
    }

    /* Keep several open tabs consistent. */
    window.addEventListener('storage', function (event) {
        if (event.key !== STORAGE_KEY) return;
        manual = event.newValue === 'dark' || event.newValue === 'light' ? event.newValue : null;
        apply(currentTheme());
    });

    function init() {
        var button = document.getElementById('theme-toggle');
        if (!button) return;
        syncButton(currentTheme());
        button.addEventListener('click', function () {
            manual = currentTheme() === 'dark' ? 'light' : 'dark';
            writeStored(manual);
            apply(manual);
        });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
