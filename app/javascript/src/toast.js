import { Toast } from "bootstrap";

const TYPE_CLASSES = {
  success: "text-bg-success",
  error: "text-bg-danger",
  info: "text-bg-primary",
};

function toastContainer() {
  let container = document.getElementById("toast-container");
  if (!container) {
    container = document.createElement("div");
    container.id = "toast-container";
    container.className = "toast-container position-fixed top-0 end-0 p-3";
    container.style.zIndex = "1090";
    document.body.append(container);
  }
  return container;
}

function toastBody(message, link) {
  const body = document.createElement("div");
  body.className = "toast-body";
  body.append(message);
  if (link) {
    const anchor = document.createElement("a");
    anchor.href = link.href;
    anchor.className = "link-light fw-semibold";
    anchor.textContent = link.text;
    body.append(anchor);
  }
  return body;
}

function closeButton() {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "btn-close btn-close-white me-2 m-auto";
  button.setAttribute("data-bs-dismiss", "toast");
  button.setAttribute("aria-label", "Close");
  return button;
}

// Shows a Bootstrap toast in the top right corner. The message is always
// text; a link ({ text, href }) can follow it.
export function showToast(message, { type = "info", link = null } = {}) {
  const element = document.createElement("div");
  element.className = `toast align-items-center border-0 ${TYPE_CLASSES[type] || TYPE_CLASSES.info}`;
  element.setAttribute("role", "alert");
  element.setAttribute("aria-live", "assertive");
  element.setAttribute("aria-atomic", "true");

  const row = document.createElement("div");
  row.className = "d-flex";
  row.append(toastBody(message, link), closeButton());
  element.append(row);

  toastContainer().append(element);
  element.addEventListener("hidden.bs.toast", () => element.remove());
  Toast.getOrCreateInstance(element, { delay: 5000 }).show();
}

// JS responses rendered by the server (which cannot import this module)
// raise a toast with: document.dispatchEvent(new CustomEvent("toast:show", { detail: { message, type, link } }))
document.addEventListener("toast:show", (event) => {
  const { message, ...options } = /** @type {CustomEvent} */ (event).detail;
  showToast(message, options);
});
