import { flatpickrOptions } from "../src/page_locale.js";
import { newTomSelect } from "../src/tom_select.js";
import { bindOnce } from "../src/bind_once.js";
import "flatpickr";

// Every visit to an admin key page, the first one and each Turbo visit or
// restore after it.
document.addEventListener("turbo:load", () => {
  setUpDepositDatePicker();
  setUpNameSearch("supervisor-select");
  setUpNotesToggle();
  setUpNameSearch("space-select");
  setUpNameSearch("key-request-select");
  setUpKeyTypeToggle();
  setUpPrintButton();
});

function setUpDepositDatePicker() {
  bindOnce(document.getElementById("deposit-return-date"), bindDepositDate);
}

function bindDepositDate(depositDateInput) {
  const depositDatePicker = depositDateInput.flatpickr(
    flatpickrOptions(depositDateInput, {
      enableTime: false,
      noCalendar: false,
      dateFormat: "Y-m-d",
    }),
  );

  const clearButton = document.getElementById("deposit-return-date-clear");
  if (!clearButton) return;
  clearButton.addEventListener("click", () => {
    depositDatePicker.clear();
  });
}

// A select whose options are searched by name, unless it already has a widget
function setUpNameSearch(id) {
  const select = document.getElementById(id);
  if (select && !select.tomselect) {
    newTomSelect(select, {
      searchField: ["name"],
      valueField: "id",
      labelField: "name",
      maxOptions: null,
      searchOnKeyUp: true,
    });
  }
}

// The notes are hidden for a key in inventory
function setUpNotesToggle() {
  const statusSelect = document.getElementById("status-select");
  const notesField = document.getElementById("notes-container");
  if (!notesField) return;

  bindOnce(statusSelect, () =>
    statusSelect.addEventListener("change", (e) => {
      notesField.style.display =
        e.target.value === "inventory" ? "none" : "block";
    }),
  );
}

// Shows or hides the box around a field, when the page has that field.
function showFieldBox(field, shown) {
  if (field) field.parentElement.style.display = shown ? "block" : "none";
}

// A regular key belongs to a space; any other key type has its own keycode
function setUpKeyTypeToggle() {
  const spaceSelect = document.getElementById("space-select");
  const customKeycode = document.getElementById("custom-keycode");
  const keyTypeSelect = document.getElementById("key-type-select");

  bindOnce(keyTypeSelect, () =>
    keyTypeSelect.addEventListener("change", (e) => {
      const regular = e.target.value === "regular";
      showFieldBox(spaceSelect, regular);
      showFieldBox(customKeycode, !regular);
    }),
  );
}

// Printing reloads the certificate frames first and prints one second after
// the last of them has loaded again.
function setUpPrintButton() {
  bindOnce(document.getElementById("print-button"), bindPrintButton);
}

function bindPrintButton(printButton) {
  const keyCertIframes = document.querySelectorAll(".key-cert-iframe");
  let loadedIframes = 0;
  let shouldPrint = false;

  keyCertIframes.forEach((iframe) => {
    iframe.addEventListener("load", () => {
      loadedIframes++;

      if (shouldPrint && loadedIframes === keyCertIframes.length) {
        setTimeout(() => {
          window.print();
        }, 1000);
      }
    });
  });

  printButton.addEventListener("click", () => {
    if (keyCertIframes.length === 0) {
      window.print();
    } else {
      loadedIframes = 0;
      shouldPrint = true;
      keyCertIframes.forEach((iframe) => {
        iframe.src = iframe.getAttribute("src");
      });
    }
  });
}
