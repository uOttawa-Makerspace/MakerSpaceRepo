import TomSelect from "tom-select";

document.addEventListener("turbo:load", () => {
  new TomSelect("#jo-staff-select", {
    searchField: ["name"],
    valueField: "id",
    labelField: "name",
    maxOptions: 10,
    searchPlaceholder: "Choose staff...",
    closeAfterSelect: true,
    create: false,
    render: {
      item: function (data, escape) {
        return `<div class="bg-light rounded-2 p-1">${escape(data.name)}</div>`;
      },
      option: function (data, escape) {
        return `<div>${escape(data.name)}</div>`;
      },
    },
  });
});
