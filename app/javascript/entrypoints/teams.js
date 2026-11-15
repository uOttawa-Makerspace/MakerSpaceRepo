import { onEveryPageLoad } from "../src/on_page.js";
import { tomSelectFor } from "../src/tom_select.js";

onEveryPageLoad(() => {
  const searchUsersAdd = document.getElementById("search_users_add");
  if (searchUsersAdd) {
    tomSelectFor(searchUsersAdd, {
      searchField: ["username"],
      valueField: "id",
      labelField: "username",
      maxOptions: 5,
      searchPlaceholder: "Add Team Captain...",
      searchOnKeyUp: true,
      load: function (type, callback) {
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
              }),
            );
          });
      },
      shouldLoad: function (type) {
        return type.length > 2;
      },
    });
  }

  const editCaptainSelect = document.getElementById("edit_captain_select");
  if (editCaptainSelect) {
    tomSelectFor(editCaptainSelect, {
      searchField: ["name"],
      valueField: "id",
      labelField: "name",
      maxOptions: null,
      searchOnKeyUp: true,
    });
  }
});
