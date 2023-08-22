import TomSelect from "tom-select";

// const depositDateInput = document.getElementById("deposit-return-date");
// if (depositDateInput) {
//   const depositDatePicker = depositDateInput.flatpickr({
//     enableTime: false,
//     noCalendar: false,
//     dateFormat: "Y-m-d",
//   });
//
//   document
//     .getElementById("deposit-return-date-clear")
//     .addEventListener("click", () => {
//       depositDatePicker.clear();
//     });
// }

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

const keyTypeSelect = document.getElementById("key-type-select");
if (keyTypeSelect) {
  keyTypeSelect.addEventListener("change", (e) => {
    if (e.target.value === "regular") {
      spaceSelect.parentElement.style.display = "block";
    } else {
      spaceSelect.parentElement.style.display = "none";
    }
  });
}
