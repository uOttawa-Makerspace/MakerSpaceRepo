// app/javascript/entrypoints/volunteer_tasks.js
import TomSelect from "tom-select";
import { tomSelectOptions } from "../src/page_locale.js";

// A page Turbo restores from its cache is a copy of the page as it was left: a
// select on it still carries the markup of its TomSelect, but no TomSelect.
// That markup is removed first, so the new TomSelect replaces it rather than
// adding a second one beside it.
function clearCachedTomSelect(el) {
  if (!el.classList.contains("tomselected")) return;
  const wrapper = el.nextElementSibling;
  if (wrapper && wrapper.classList.contains("ts-wrapper")) wrapper.remove();
  el.classList.remove("tomselected", "ts-hidden-accessible");
}

function newTomSelect(el, options) {
  clearCachedTomSelect(el);
  return new TomSelect(el, tomSelectOptions(el, options));
}

function initTomSelect(selector, options) {
  const el = document.querySelector(selector);
  if (el && !el.tomselect) newTomSelect(el, options);
}

// The elements this script has already bound: a second load over the same
// page binds nothing twice. A page Turbo restores from its cache is a copy made
// of new elements, which are bound again.
const boundElements = new WeakSet();

function bindOnce(el, bind) {
  if (boundElements.has(el)) return;
  boundElements.add(el);
  bind(el);
}

function bindImageRemoval(el) {
  el.addEventListener("click", (e) => {
    e.preventDefault();
    e.stopPropagation();
    const deleteImagesInput = document.getElementById("deleteimages");
    if (deleteImagesInput) {
      deleteImagesInput.value += el.id + ",";
    }
    el.parentElement.remove();
  });
}

function bindImageRemovals() {
  document
    .querySelectorAll(".image-remove")
    .forEach((el) => bindOnce(el, bindImageRemoval));
}

// The TomSelect of a filter select: the one an earlier load of the same page
// made, or a new one. Null when the page has no such select.
function filterSelect(el, options) {
  if (!el) return null;
  return el.tomselect || newTomSelect(el, options);
}

function selectedValue(tom) {
  return tom ? tom.getValue().toLowerCase() : "";
}

function currentTaskFilters(searchInput, spaceTom, categoryTom, certTom) {
  return {
    query: searchInput ? searchInput.value.toLowerCase().trim() : "",
    space: selectedValue(spaceTom),
    category: selectedValue(categoryTom),
    certs: certTom ? certTom.getValue() : [],
  };
}

function cardAttribute(card, name) {
  return (card.getAttribute(name) || "").toLowerCase();
}

// Every filter is checked, then combined: a card shows only when it matches
// the search text (anywhere), the space and category (exactly) and at least
// one of the chosen certifications (by part of its name). Empty filters match.
function cardMatchesFilters(card, filters) {
  const certs = cardAttribute(card, "data-certifications");
  const matches = [
    !filters.query ||
      cardAttribute(card, "data-searchable-text").includes(filters.query),
    !filters.space || cardAttribute(card, "data-space") === filters.space,
    !filters.category ||
      cardAttribute(card, "data-category") === filters.category,
    filters.certs.length === 0 ||
      filters.certs.some((cert) => certs.includes(cert.toLowerCase())),
  ];
  return matches.every(Boolean);
}

function applyTaskCardFilters(container, filters) {
  container.querySelectorAll(".task-item-card-col").forEach((card) => {
    card.style.display = cardMatchesFilters(card, filters) ? "" : "none";
  });
}

function initTaskIndexFilters(taskIndexContainer) {
  const spaceEl = document.getElementById("spaceFilter");
  const categoryEl = document.getElementById("categoryFilter");
  const certEl = document.getElementById("certFilter");
  const searchInput = document.getElementById("taskSearchInput");

  const spaceTom = filterSelect(spaceEl, {
    allowEmptyOption: true,
    create: false,
    controlInput: null,
  });
  const categoryTom = filterSelect(categoryEl, {
    allowEmptyOption: true,
    create: false,
    controlInput: null,
  });
  const certTom = filterSelect(certEl, {
    plugins: ["remove_button"],
    create: false,
  });

  function applyFilters() {
    applyTaskCardFilters(
      taskIndexContainer,
      currentTaskFilters(searchInput, spaceTom, categoryTom, certTom),
    );
  }

  if (searchInput) searchInput.addEventListener("input", applyFilters);
  [spaceTom, categoryTom, certTom].forEach((tom) => {
    if (tom) tom.on("change", applyFilters);
  });
}

document.addEventListener("turbo:load", function () {
  // ------------------------------------------------------------------------
  // 1. Task Form TomSelects
  // ------------------------------------------------------------------------
  initTomSelect("#user_id", {
    placeholder: "Select a user",
    maxItems: 1,
    plugins: ["remove_button"],
  });

  initTomSelect("#task_certifications", {
    plugins: ["remove_button"],
    maxItems: null,
    sortField: [{ field: "text" }],
  });

  initTomSelect("#volunteer_id", {
    plugins: ["remove_button"],
    maxItems: null,
    sortField: [{ field: "text" }],
  });

  initTomSelect("#staff_id", {
    maxItems: 1,
    sortField: [{ field: "text" }],
  });

  initTomSelect("#remove_staff_id", {
    plugins: ["remove_button"],
    maxItems: null,
    closeAfterSelect: true,
  });

  initTomSelect("#remove_volunteer_id", {
    plugins: ["remove_button"],
    maxItems: null,
    closeAfterSelect: true,
  });

  // ------------------------------------------------------------------------
  // 2. Task Form Image Removals
  // ------------------------------------------------------------------------
  bindImageRemovals();

  // ------------------------------------------------------------------------
  // 3. Volunteer Tasks Index Filter & Search Engine
  // ------------------------------------------------------------------------
  const taskIndexContainer = document.getElementById("volunteerTasksIndex");
  if (taskIndexContainer) bindOnce(taskIndexContainer, initTaskIndexFilters);
});
