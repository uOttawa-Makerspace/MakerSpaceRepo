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

// Single rule for "Turbo is off for this element": everything without .useTurbo.
const turboOff = (el) => !el.classList.contains("useTurbo");
const disableTurboUnlessOptedIn = (root = document) => {
  root.querySelectorAll("form, a").forEach((el) => {
    if (turboOff(el)) el.dataset.turbo = "false";
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
// on elements it handles (.useTurbo); everything else, and legacy data-confirm
// (rails-ujs is not loaded), is prompted here. Handling an element also marks it
// data-turbo=false (the same rule as the turbo:load pass), so a click before
// turbo:load neither skips the prompt nor lets Turbo prompt again.
const confirmMessage = (off, ...elements) => {
  const turbo = elements.find((el) => el?.dataset.turboConfirm);
  if (turbo) return off ? turbo.dataset.turboConfirm : null;
  return elements.find((el) => el?.dataset.confirm)?.dataset.confirm || null;
};

const declined = (event, off, ...elements) => {
  const msg = confirmMessage(off, ...elements);
  if (!msg || window.confirm(msg)) return false;
  event.preventDefault();
  event.stopImmediatePropagation();
  return true;
};

document.addEventListener(
  "submit",
  (event) => {
    const form = event.target;
    if (!(form instanceof HTMLFormElement)) return;
    const off = turboOff(form);
    if (off) form.dataset.turbo = "false";
    declined(event, off, event.submitter, form);
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
    const off = turboOff(link);
    if (off) link.dataset.turbo = "false";
    declined(event, off, link);
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
