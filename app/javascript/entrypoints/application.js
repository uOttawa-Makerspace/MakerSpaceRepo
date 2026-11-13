/* eslint no-console:0 */
import "trix";

// Imported from ../src/
import "../src/validation";
import "../src/direct_uploads";
import "../src/effects";
import "../src/forms";
import "../src/header";
import "../src/photo_gallery";
import "../src/requests";
import { csrfHeaders } from "../src/csrf";
import { reportFailure, requestJson } from "../src/request_error";
import "../src/settings";
import "../src/sorting";
import "../src/tabledata";
import "../src/accordion-load";
import "../src/clipboard";
import "../src/theme";
import "../src/calendar_saved";

// Stimulus controllers
import "../controllers";

// Eager load images
import.meta.glob("../images/**", { eager: true });

import { Tooltip, Popover } from "bootstrap";
import "@hotwired/turbo-rails";

document.addEventListener("turbo:before-render", (event) => {
  event.detail.newBody
    .querySelectorAll("#noscript-warning")
    .forEach((element) => {
      element.remove();
    });
});

// The load-time rule for server-rendered markup: everything without .useTurbo
// is forced to data-turbo=false, even when the markup says data-turbo="true"
// (the calendar links rely on full page loads).
const turboOptedOut = (el) => !el.classList.contains("useTurbo");
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

window.setSpace = async function () {
  const spaceIdInput = document.getElementById("set_space_id");
  if (!spaceIdInput) return;

  const space_id = spaceIdInput.value;
  const url = "/staff_dashboard/change_space";

  try {
    await requestJson(url, {
      method: "PUT",
      credentials: "include",
      headers: csrfHeaders({
        "Content-Type": "application/json",
        Accept: "application/json",
      }),
      body: JSON.stringify({
        space_id: space_id,
        training: window.location.href.includes("training_sessions"),
        questions: window.location.href.includes("questions"),
        shifts: window.location.href.includes("shifts"),
      }),
    });
    window.location.reload();
  } catch (error) {
    reportFailure(error);
  }
};

/** @type {any} */ (window).debounce = function (func, wait, immediate) {
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
  try {
    await requestJson("/exam_responses#create", {
      method: "POST",
      headers: csrfHeaders({ "Content-Type": "application/json" }),
      body: JSON.stringify({
        exam_id: exam_id,
        answer_id: answer_id,
      }),
    });
  } catch (error) {
    reportFailure(error);
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

// Last statement of the entry: the page script has run. Specs wait on this flag
// before their first click.
document.documentElement.dataset.appJsReady = "true";
