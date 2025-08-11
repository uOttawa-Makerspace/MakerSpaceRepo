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
import "regenerator-runtime/runtime";
import "trix";
import "@shopify/buy-button-js";
import "photoswipe";
import "clipboard";
import "flatpickr";
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

import "bootstrap";
import "toastr/toastr";

import "@hotwired/turbo-rails";
import { Turbo } from "@hotwired/turbo-rails";
import { Tooltip } from "bootstrap";

document.addEventListener("turbo:before-render", (event) => {
  event.detail.newBody
    .querySelectorAll("#noscript-warning")
    .forEach((element) => {
      element.remove();
    });
});

document.addEventListener("turbo:load", () => {
  let tooltips = document.querySelectorAll('[data-bs-toggle="tooltip"]');
  tooltips.forEach((tooltip) => {
    return new Tooltip(tooltip);
  });
  let popovers = document.querySelectorAll('[data-bs-toggle="popover"]');
  popovers.forEach((popover) => {
    return new bootstrap.Popover(popover);
  });

  const links = document.getElementsByTagName("a");

  for (let i = 0; i < links.length; i++) {
    const link = links[i];
    const href = link.getAttribute("href");
    if (href !== null && href.match(/^((https?:\/\/)|(www\.))/)) {
      link.setAttribute("target", "_blank");
      link.setAttribute("rel", "noopener noreferrer");
    }
  }
});

window.clearEndDate = function () {
  document.getElementById("end_date").value = null;
};

window.setSpace = function () {
  let space_id = document.getElementById("set_space_id").value;
  let url = "/staff_dashboard/change_space";
  fetch(url, {
    method: "PUT",
    credentials: "include",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify({
      space_id: space_id,
      training: document.URL.includes("training_sessions"),
      questions: document.URL.includes("questions"),
      shifts: document.URL.includes("shifts"),
    }),
  })
    .then((response) => response.json())
    .then((data) => {
      window.location.reload();
    })
    .catch((error) => {
      console.log(error);
    });
};

window.debounce = function (func, wait, immediate) {
  let timeout;
  return function () {
    let context = this,
      args = arguments;
    let later = function () {
      timeout = null;
      if (!immediate) func.apply(context, args);
    };
    let callNow = immediate && !timeout;
    clearTimeout(timeout);
    timeout = setTimeout(later, wait);
    if (callNow) func.apply(context, args);
  };
};
window.examResponse = function (exam_id, answer_id) {
  fetch("/exam_responses#create", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      exam_id: exam_id,
      answer_id: answer_id,
    }),
  });
};
window.dragndrop = function (event) {
  event.preventDefault();
  let images = [...document.getElementsByClassName("image-upload")];
  for (let i = 0; i < images.length; i++) {
    if (images[i].files.length == 0) {
      images[i].files = event.dataTransfer.files;
      break;
    }
  }
};
window.dragover = function (event) {
  event.preventDefault();
};
// Replaces the jQuery confirm on button_to data=>confirm
document.addEventListener("turbo:load", () => {
  [...document.getElementsByTagName("button")].forEach((button) => {
    button.addEventListener("click", (event) => {
      if (button.dataset.confirm) {
        if (!confirm(button.dataset.confirm)) {
          event.preventDefault();
        }
      }
    });
  });
});
document.addEventListener("turbo:load", () => {
  document.querySelectorAll("form:not(.useTurbo)").forEach(function (el) {
    el.dataset.turbo = false;
  });
  document.querySelectorAll("a").forEach(function (el) {
    el.dataset.turbo = false;
  });
});
