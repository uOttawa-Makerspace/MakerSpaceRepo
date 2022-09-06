let staff_select = document.getElementById("new_staff_select");
if (staff_select) {
  if (!staff_select.tomselect) {
    new TomSelect("#new_staff_select", {
      searchField: ["name"],
      valueField: "id",
      labelField: "name",
      options: [],
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
                  return { id: user.username, name: user.name };
                })
              );
            });
        }
      },
      shouldLoad: function (type) {
        return type.length > 2;
      },
      onItemAdd: function (value, item) {
        let tselect = this;
        let listItem = document.createElement("span");
        listItem.setAttribute("data-id", value);
        listItem.setAttribute("class", "d-block");

        let remove = document.createElement("btn");
        remove.setAttribute("class", "fa fa-times x-button");
        remove.addEventListener("click", () => {
          remove.parentElement.remove();
          document.getElementById("user_ids_").value = Array.from(
            document.getElementById("new-staff-list").children
          ).map((child) => child.dataset.id);
          tselect.addOption(value, false);
        });

        listItem.appendChild(remove);
        let label = document.createElement("a");
        label.setAttribute("class", "form-check-label ms-2");
        label.innerHTML = item.innerText;
        label.setAttribute("href", "/" + value);
        listItem.appendChild(label);

        document.getElementById("new-staff-list").appendChild(listItem);
        tselect.removeOption(value);
        document.getElementById("new_staff_select-ts-control").value = "";
        document.getElementById("user_ids_").value = Array.from(
          document.getElementById("new-staff-list").children
        ).map((child) => child.dataset.id);
      },
    });
  }
}
