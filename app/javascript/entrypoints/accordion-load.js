/**
 * This class stores information about accordion states in local storage and sets states on page load.
 */

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
          document.getElementById(item).classList.add("show");
        }
      } else if (storage[item] === false) {
        if (document.getElementById(item)) {
          document.getElementById(item).classList.remove("show");
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
