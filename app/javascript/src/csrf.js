// The page's CSRF token, from csrf_meta_tags (every layout renders it).
// Every non-GET fetch to this app sends it as X-CSRF-Token: the server checks
// it on every HTML/JS request (ApplicationController, protect_from_forgery).
export function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content ?? "";
}

// The form field name Rails reads the token from (csrf-param meta tag).
export function csrfParam() {
  return document.querySelector('meta[name="csrf-param"]')?.content ?? "authenticity_token";
}

// Request headers plus X-CSRF-Token.
export function csrfHeaders(headers = {}) {
  return { ...headers, "X-CSRF-Token": csrfToken() };
}
