/* eslint no-console:0 */
import "trix";
import "clipboard";

// Imported from ../src/
import "../src/validation";
import "../src/direct_uploads";
import "../src/effects";
import "../src/forms";
import "../src/header";
import "../src/photo_gallery";
import "../src/requests";
import "../src/settings";
import "../src/sorting";
import "../src/tabledata";
import "../src/accordion-load";
import "../src/clipboard";
import "../src/theme";

// Stimulus controllers
import "../controllers";

// Eager load images
import.meta.glob("../images/**", { eager: true });

import { Tooltip, Popover } from "bootstrap";
import "toastr/toastr";
import "@hotwired/turbo-rails";

document.addEventListener("turbo:before-render", (event) => {
  event.detail.newBody
    .querySelectorAll("#noscript-warning")
    .forEach((element) => {
      element.remove();
    });
});

// Two predicates, deliberately different:
// - turboOptedOut: the load-time rule for server-rendered markup. Everything
//   without .useTurbo is forced to data-turbo=false, even when the markup says
//   data-turbo="true" (the calendar links rely on full page loads).
// - turboOffAtEvent: used by the confirm handler at event time. Elements that say
//   data-turbo="true" there are Turbo's own hidden forms (built after load for
//   data-turbo-method links); marking them off would submit a DELETE as a GET.
const turboOptedOut = (el) => !el.classList.contains("useTurbo");
const turboOffAtEvent = (el) =>
  el.dataset.turbo !== "true" && turboOptedOut(el);
const disableTurboUnlessOptedIn = (root = document) => {
  root.querySelectorAll("form, a").forEach((el) => {
    if (turboOptedOut(el)) el.dataset.turbo = "false";
  });
};

document.addEventListener("turbo:load", () => {
  // Initialize Bootstrap Tooltips
  document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach((el) => {
    new Tooltip(el);
  });

  // Initialize Bootstrap Popovers
  document.querySelectorAll('[data-bs-toggle="popover"]').forEach((el) => {
    new Popover(el);
  });

  // External link target handler
  document.querySelectorAll("a[href]").forEach((link) => {
    const href = link.getAttribute("href");
    if (href && href.match(/^((https?:)?\/\/)/)) {
      link.setAttribute("target", "_blank");
      link.setAttribute("rel", "noopener noreferrer");
    }
  });

  // Disable Turbo on forms/links not explicitly opted in
  disableTurboUnlessOptedIn();
});

// Confirmations Turbo does not show. Turbo prompts only for data-turbo-confirm
// on elements it handles; everything else (Turbo off, legacy data-confirm since
// rails-ujs is not loaded, a Turbo link without data-turbo-method, which Turbo 8
// does not prompt for) is prompted here. The first of `sources` (submitter before
// form) that carries a message decides. Handling an element also marks it
// data-turbo=false (turboOffAtEvent, which unlike the load pass's turboOptedOut
// spares Turbo's own data-turbo="true" hidden forms), so a click before
// turbo:load neither skips the prompt nor lets Turbo prompt again.
const confirmMessage = (turboPrompts, sources) => {
  for (const el of sources) {
    if (!el) continue;
    if (el.dataset.turboConfirm) return turboPrompts ? null : el.dataset.turboConfirm;
    if (el.dataset.confirm) return el.dataset.confirm;
  }
  return null;
};

const confirmOrCancel = (event, el, { turboPrompts = false, sources = [el] } = {}) => {
  const off = turboOffAtEvent(el);
  if (off) el.dataset.turbo = "false";
  const msg = confirmMessage(!off && turboPrompts, sources);
  if (!msg || window.confirm(msg)) return;
  event.preventDefault();
  event.stopImmediatePropagation();
};

document.addEventListener(
  "submit",
  (event) => {
    const form = event.target;
    if (!(form instanceof HTMLFormElement)) return;
    confirmOrCancel(event, form, { turboPrompts: true, sources: [event.submitter, form] });
  },
  true,
);

document.addEventListener(
  "click",
  (event) => {
    const link =
      event.target instanceof Element &&
      event.target.closest("a[data-turbo-confirm], a[data-confirm]");
    if (!link) return;
    confirmOrCancel(event, link, { turboPrompts: Boolean(link.dataset.turboMethod) });
  },
  true,
);

window.clearEndDate = function () {
  const endDate = document.getElementById("end_date");
  if (endDate) endDate.value = "";
};

window.setSpace = async function () {
  const spaceIdInput = document.getElementById("set_space_id");
  if (!spaceIdInput) return;

  const space_id = spaceIdInput.value;
  const url = "/staff_dashboard/change_space";
  const csrfToken = document
    .querySelector('meta[name="csrf-token"]')
    ?.getAttribute("content");

  try {
    const response = await fetch(url, {
      method: "PUT",
      credentials: "include",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": csrfToken || "",
      },
      body: JSON.stringify({
        space_id: space_id,
        training: window.location.href.includes("training_sessions"),
        questions: window.location.href.includes("questions"),
        shifts: window.location.href.includes("shifts"),
      }),
    });

    if (response.ok) {
      window.location.reload();
    }
  } catch (error) {
    console.error("Failed to update space:", error);
  }
};

window.debounce = function (func, wait, immediate) {
  let timeout;
  return function (...args) {
    const context = this;
    const later = function () {
      timeout = null;
      if (!immediate) func.apply(context, args);
    };
    const callNow = immediate && !timeout;
    clearTimeout(timeout);
    timeout = setTimeout(later, wait);
    if (callNow) func.apply(context, args);
  };
};

window.examResponse = async function (exam_id, answer_id) {
  const csrfToken = document
    .querySelector('meta[name="csrf-token"]')
    ?.getAttribute("content");
  try {
    await fetch("/exam_responses#create", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken || "",
      },
      body: JSON.stringify({
        exam_id: exam_id,
        answer_id: answer_id,
      }),
    });
  } catch (error) {
    console.error("Exam response error:", error);
  }
};

window.dragndrop = function (event) {
  event.preventDefault();
  const images = [...document.getElementsByClassName("image-upload")];
  for (let i = 0; i < images.length; i++) {
    if (images[i].files.length === 0) {
      images[i].files = event.dataTransfer.files;
      break;
    }
  }
};

window.dragover = function (event) {
  event.preventDefault();
};

// Last statement of the entry: the confirm listeners above are registered.
// Specs wait on this flag before any data-confirm click.
document.documentElement.dataset.appJsReady = "true";
