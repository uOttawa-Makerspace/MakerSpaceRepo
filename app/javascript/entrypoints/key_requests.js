import TomSelect from "tom-select";

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

let deleteFiles = document.getElementById("delete_files");
[...document.getElementsByClassName("file-remove")].forEach((el) => {
  el.addEventListener("click", (e) => {
    e.preventDefault();
    e.stopPropagation();
    deleteFiles.value += el.id + ",";
    el.parentElement.parentElement.remove();
  });
});
