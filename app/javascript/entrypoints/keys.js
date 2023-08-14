import TomSelect from "tom-select";

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

const defaultUser = document.getElementById("default-user");

let userSelect = document.getElementById("user-select");
if (userSelect && !userSelect.tomselect) {
  let options = [];
  let items = [];

  if (defaultUser) {
    const defaultUserData = defaultUser.value.split(",");
    const defaultUserId = defaultUserData[0];
    const defaultUserName = defaultUserData[1];
    options = [{ id: defaultUserId, name: defaultUserName }];
    items = [defaultUserId];
  }
  new TomSelect("#user-select", {
    searchField: ["name"],
    valueField: "id",
    labelField: "name",
    options: options,
    items: items,
    maxOptions: 5,
    searchPlaceholder: "Choose User...",
    searchOnKeyUp: true,
    load: function (type, callback) {
      if (type.length < 2) {
        return;
      } else {
        fetch(`/repositories/populate_users?search=${type}`)
          .then((response) => response.json())
          .then((data) => {
            callback(
              data.users.map((user) => {
                return { id: user.id, name: user.name };
              })
            );
          });
      }
    },
    shouldLoad: function (type) {
      return type.length > 2;
    },
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
