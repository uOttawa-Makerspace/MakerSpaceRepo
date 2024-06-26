import TomSelect from "tom-select";

document.addEventListener("DOMContentLoaded", () => {
  const depositDateInput = document.getElementById("deposit-return-date");
  if (depositDateInput) {
    const depositDatePicker = depositDateInput.flatpickr({
      enableTime: false,
      noCalendar: false,
      dateFormat: "Y-m-d",
    });

    document
      .getElementById("deposit-return-date-clear")
      .addEventListener("click", () => {
        depositDatePicker.clear();
      });
  }

  let supervisorSelect = document.getElementById("supervisor-select");
  if (supervisorSelect && !supervisorSelect.tomselect) {
    new TomSelect("#supervisor-select", {
      searchField: ["name"],
      valueField: "id",
      labelField: "name",
      maxOptions: null,
      searchOnKeyUp: true,
    });
  }

  const statusSelect = document.getElementById("status-select");
  const notesField = document.getElementById("notes-container");
  if (statusSelect && notesField) {
    statusSelect.addEventListener("change", (e) => {
      if (e.target.value === "inventory") {
        notesField.style.display = "none";
      } else {
        notesField.style.display = "block";
      }
    });
  }

  let spaceSelect = document.getElementById("space-select");
  if (spaceSelect && !spaceSelect.tomselect) {
    new TomSelect("#space-select", {
      searchField: ["name"],
      valueField: "id",
      labelField: "name",
      maxOptions: null,
      searchOnKeyUp: true,
    });
  }

  let keyRequestSelect = document.getElementById("key-request-select");
  if (keyRequestSelect && !keyRequestSelect.tomselect) {
    new TomSelect("#key-request-select", {
      searchField: ["name"],
      valueField: "id",
      labelField: "name",
      maxOptions: null,
      searchOnKeyUp: true,
    });
  }

  const customKeycode = document.getElementById("custom-keycode");
  const keyTypeSelect = document.getElementById("key-type-select");
  if (keyTypeSelect) {
    keyTypeSelect.addEventListener("change", (e) => {
      if (e.target.value === "regular") {
        spaceSelect.parentElement.style.display = "block";
        customKeycode.parentElement.style.display = "none";
      } else {
        spaceSelect.parentElement.style.display = "none";
        customKeycode.parentElement.style.display = "block";
      }
    });
  }

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
});
