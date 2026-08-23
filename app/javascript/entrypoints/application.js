/* eslint no-console:0 */
// This file is automatically compiled by Webpack, along with any other files
// present in this directory. You're encouraged to place your actual application logic in
// a relevant structure within app/javascript and only use these pack files to reference
// that code so it'll be compiled.
//
// To reference this file, add <%= vite_javascript_tag 'application' %> to the appropriate
// layout file, like app/views/layouts/application.html.erb

// Uncomment to copy all static images under ../images to the output folder and reference
// them with the image_pack_tag helper in views (e.g <%= image_pack_tag 'rails.png' %>)
// or the `imagePath` JavaScript helper below.
//
// const images = require.context('../images', true)
// const imagePath = (name) => images(name, true)
import "trix";
import "photoswipe";
import "clipboard";
import "./validation";
import "./direct_uploads";
import "./effects";
import "./forms";
import "./header";
import "./photo_gallery";
import "./requests";
import "./settings";
import "./sorting";
import "./tabledata";
import "./accordion-load";
import "./clipboard";
import "../controllers";
import "./theme";

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
  document.querySelectorAll("form:not(.useTurbo)").forEach((el) => {
    el.dataset.turbo = "false";
  });
  document.querySelectorAll("a:not(.useTurbo)").forEach((el) => {
    el.dataset.turbo = "false";
  });
});

// Confirmation handler for button_to data-confirm
document.addEventListener("turbo:load", () => {
  document.querySelectorAll("button[data-confirm]").forEach((button) => {
    button.addEventListener("click", (event) => {
      if (!confirm(button.dataset.confirm)) {
        event.preventDefault();
      }
    });
  });
});

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
