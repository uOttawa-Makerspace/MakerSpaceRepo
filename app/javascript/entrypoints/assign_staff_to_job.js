import { tomSelectFor } from "../src/tom_select.js";

document.addEventListener("turbo:load", () => {
  const staffSelect = document.getElementById("jo-staff-select");
  if (!staffSelect) return;
  tomSelectFor(staffSelect, {
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
});
