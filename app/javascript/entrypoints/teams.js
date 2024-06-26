import TomSelect from "tom-select";

document.addEventListener("turbo:load", () => {
  const searchUsersAdd = document.getElementById("search_users_add");
  if (searchUsersAdd && !searchUsersAdd.tomselect) {
    new TomSelect("#search_users_add", {
      searchField: ["username"],
      valueField: "id",
      labelField: "username",
      maxOptions: 5,
      searchPlaceholder: "Add Team Captain...",
      searchOnKeyUp: true,
      load: function (type, callback) {
        if (type.length < 2) {
          return;
        } else {
          let url = "/repositories/populate_users?search=" + type;
          fetch(url)
            .then((response) => response.json())
            .then((data) => {
              callback(
                data.users.map((user) => {
                  return {
                    id: user.id,
                    username: user.name + " (" + user.username + ")",
                  };
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

  const editCaptainSelect = document.getElementById("edit_captain_select");
  if (editCaptainSelect && !editCaptainSelect.tomselect) {
    new TomSelect("#edit_captain_select", {
      searchField: ["name"],
      valueField: "id",
      labelField: "name",
      maxOptions: null,
      searchOnKeyUp: true,
    });
  }
});
