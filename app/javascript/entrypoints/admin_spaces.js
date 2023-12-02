import TomSelect from "tom-select";

document.addEventListener("turbo:load", () => {
  const spaceManagerSelect = document.getElementById("space-manager-select");
  if (spaceManagerSelect && !spaceManagerSelect.tomselect) {
    new TomSelect("#space-manager-select", {
      searchField: ["name"],
      valueField: "id",
      labelField: "name",
      maxOptions: null,
      searchOnKeyUp: true,
    });
  }
});
