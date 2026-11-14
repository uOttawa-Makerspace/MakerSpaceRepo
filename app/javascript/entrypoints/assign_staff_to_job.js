import { tomSelectFor } from "../src/tom_select.js";

// A fresh set for each picker: TomSelect keeps the object it is given.
const staffPickerOptions = () => ({
  searchField: ["name"],
  valueField: "id",
  labelField: "name",
  maxOptions: 10,
  searchPlaceholder: "Choose staff...",
  closeAfterSelect: true,
  create: false,
  render: {
    item: function (data, escape) {
      return `<div class="bg-body-secondary rounded-2 p-1">${escape(data.name)}</div>`;
    },
    option: function (data, escape) {
      return `<div>${escape(data.name)}</div>`;
    },
  },
});

// Every staff select on the page: one on a job order, one per row on the
// admin job order list.
document.addEventListener("turbo:load", () => {
  document
    .querySelectorAll("select.jo-staff-select")
    .forEach((staffSelect) => tomSelectFor(staffSelect, staffPickerOptions()));
});
