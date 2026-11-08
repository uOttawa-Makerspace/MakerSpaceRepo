# Javascript

Javascript for all views is located in `app/javascript/entrypoints`.

# Toasts, copy buttons and checks

- Toasts use Bootstrap's Toast component through `app/javascript/src/toast.js` (`showToast(message, { type, link })`; messages are always text). Server-rendered JS responses raise one with a `toast:show` document event. toastr is no longer used.
- Buttons with class `clipboard-btn` copy their `data-clipboard-text`, or the text of the element named by `data-clipboard-target`, with `navigator.clipboard` (`app/javascript/src/clipboard.js`).
- Bootstrap classes (Toast, Modal and so on) are imported by the entrypoints that use them, not globally.
- Pages load only the entrypoints they name. A script no page loads has been removed. The staff new-training-session form loads `staff_training_sessions` with its own `vite_javascript_tag`.
- CI runs ESLint (`yarn lint:js`) and a TypeScript check (`yarn typecheck:js`). Both compare against a committed baseline (`eslint-suppressions.json`, `config/js-typecheck-baseline.txt`), so only new findings fail.

# Dropdowns

For dropdowns we have tomselect installed. See `app/javascript/entrypoints/users.js` for an example in the sign ups page
