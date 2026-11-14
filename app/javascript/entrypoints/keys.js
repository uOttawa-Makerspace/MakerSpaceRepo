import TomSelect from "tom-select";
import { flatpickrOptions, tomSelectOptions } from "../src/page_locale.js";
import "flatpickr";

document.addEventListener("DOMContentLoaded", () => {
  setUpDepositDatePicker();
  setUpNameSearch("supervisor-select");
  setUpNotesToggle();
  setUpNameSearch("space-select");
  setUpNameSearch("key-request-select");
  setUpKeyTypeToggle();
  setUpPrintButton();
});

function setUpDepositDatePicker() {
  const depositDateInput = document.getElementById("deposit-return-date");
  if (!depositDateInput) return;

  const depositDatePicker = depositDateInput.flatpickr(
    flatpickrOptions(depositDateInput, {
      enableTime: false,
      noCalendar: false,
      dateFormat: "Y-m-d",
    }),
  );

  document
    .getElementById("deposit-return-date-clear")
    .addEventListener("click", () => {
      depositDatePicker.clear();
    });
}

// A select whose options are searched by name, unless it already has a widget
function setUpNameSearch(id) {
  const select = document.getElementById(id);
  if (select && !select.tomselect) {
    new TomSelect(
      `#${id}`,
      tomSelectOptions(document, {
        searchField: ["name"],
        valueField: "id",
        labelField: "name",
        maxOptions: null,
        searchOnKeyUp: true,
      }),
    );
  }
}

// The notes are hidden for a key in inventory
function setUpNotesToggle() {
  const statusSelect = document.getElementById("status-select");
  const notesField = document.getElementById("notes-container");
  if (!statusSelect || !notesField) return;

  statusSelect.addEventListener("change", (e) => {
    notesField.style.display =
      e.target.value === "inventory" ? "none" : "block";
  });
}

// A regular key belongs to a space; any other key type has its own keycode
function setUpKeyTypeToggle() {
  const spaceSelect = document.getElementById("space-select");
  const customKeycode = document.getElementById("custom-keycode");
  const keyTypeSelect = document.getElementById("key-type-select");
  if (!keyTypeSelect) return;

  keyTypeSelect.addEventListener("change", (e) => {
    const regular = e.target.value === "regular";
    spaceSelect.parentElement.style.display = regular ? "block" : "none";
    customKeycode.parentElement.style.display = regular ? "none" : "block";
  });
}

// Printing reloads the certificate frames first and prints one second after
// the last of them has loaded again.
function setUpPrintButton() {
  const printButton = document.getElementById("print-button");
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

  if (printButton) {
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
}
