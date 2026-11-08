// Shared setup for the specs of what each script tells the user when a request fails.
import { vi } from "vitest";

export const toasts = [];

export const flush = () => new Promise((resolve) => setTimeout(resolve, 20));

// The scripts under test register listeners on the document when imported; drop them between examples.
const added = [];
const addListener = document.addEventListener.bind(document);
document.addEventListener = (type, listener, options) => {
  added.push([type, listener, options]);
  addListener(type, listener, options);
};

export function reset() {
  added
    .splice(0)
    .forEach(([type, listener, options]) =>
      document.removeEventListener(type, listener, options),
    );
  toasts.length = 0;
  document.body.innerHTML = "";
  document.documentElement.dataset.requestFailed = "Reload and retry";
  document.documentElement.dataset.requestNetwork = "Unreachable";
  document.documentElement.dataset.requestCopyFailed = "Copy by hand";
  vi.spyOn(console, "error").mockImplementation(() => {});
}

// A fetch that answers every call with a fresh response.
export const answerWith = (status, body, headers = {}) =>
  vi.fn(
    async () =>
      new Response(typeof body === "string" ? body : JSON.stringify(body), {
        status,
        headers,
      }),
  );

export const dropConnection = () =>
  vi.fn(() => Promise.reject(new TypeError("Failed to fetch")));
