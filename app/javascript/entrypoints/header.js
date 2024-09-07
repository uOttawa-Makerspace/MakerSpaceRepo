import { Turbo } from "@hotwired/turbo-rails";
/**
 *
 * This JS deals with the navbar
 * Reduce padding on scroll
 * Previously this dealt with dark mode, but the redesign does not include it
 * If needed, it must be implemented using bootstrap instead
 *
 */

document.addEventListener("turbo:load", function () {
  document.addEventListener("scroll", function () {
    // Add a small buffer between triggers
    // So header doesn't jump around when exactly on the edge
    // And actually get height of banner
    let header = document.querySelector("#sticky-header");
    let threshold = header.clientHeight;
    if (document.documentElement.scrollTop > threshold) {
      header
        .querySelectorAll(".navbar")
        .forEach((header) => header.classList.add("header-small"));
    } else if (document.documentElement.scrollTop < threshold / 2) {
      header
        .querySelectorAll(".navbar")
        .forEach((header) => header.classList.remove("header-small"));
    }
  });
});
