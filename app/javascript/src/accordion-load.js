/**
 * This class stores information about accordion states in local storage and sets states on page load.
 */

// Opens or closes a restored panel and keeps aria-expanded on its trigger buttons in step.
const setPanelOpen = (panel, open) => {
  panel.classList.toggle("show", open);
  document
    .querySelectorAll(
      `[data-bs-toggle="collapse"][data-bs-target="#${CSS.escape(panel.id)}"]`,
    )
    .forEach((trigger) => trigger.setAttribute("aria-expanded", String(open)));
};

document.addEventListener("turbo:load", () => {
  let storageString = localStorage.getItem(location.pathname);
  let storage;
  if (storageString) {
    try {
      storage = JSON.parse(storageString);
    } catch (e) {
      storage = {};
    }
    Object.keys(storage).forEach(function (item) {
      if (storage[item] === true) {
        if (document.getElementById(item)) {
          setPanelOpen(document.getElementById(item), true);
        }
      } else if (storage[item] === false) {
        if (document.getElementById(item)) {
          setPanelOpen(document.getElementById(item), false);
        }
      }
    });
  }
  const collapseElements = [...document.getElementsByClassName("collapse")];
  collapseElements.forEach((collapseElement) => {
    collapseElement.addEventListener("show.bs.collapse", (event) => {
      let storageString = localStorage.getItem(location.pathname);
      let storage;
      if (storageString) {
        try {
          storage = JSON.parse(storageString);
        } catch {
          storage = {};
        }
      } else {
        storage = {};
      }
      storage[event.target.id] = true;
      localStorage.setItem(location.pathname, JSON.stringify(storage));
    });
    collapseElement.addEventListener("hide.bs.collapse", (event) => {
      let storageString = localStorage.getItem(location.pathname);
      let storage;
      if (storageString) {
        try {
          storage = JSON.parse(storageString);
        } catch {
          storage = {};
        }
      } else {
        storage = {};
      }
      storage[event.target.id] = false;
      localStorage.setItem(location.pathname, JSON.stringify(storage));
    });
  });
});
