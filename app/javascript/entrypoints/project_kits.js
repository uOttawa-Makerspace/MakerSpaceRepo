import { onEveryPageLoad } from "../src/on_page.js";
import { tomSelectFor } from "../src/tom_select.js";

onEveryPageLoad(() => {
  const kitUserSelect = document.getElementById("kit_user_select");
  if (!kitUserSelect) return;
  tomSelectFor(kitUserSelect, {
    searchField: ["name"],
    valueField: "id",
    labelField: "name",
    options: [],
    maxOptions: 5,
    searchOnKeyUp: true,
    load: function (type, callback) {
      let url = "/project_kits/populate_kit_users?search=" + type;
      fetch(url)
        .then((response) => response.json())
        .then((data) => {
          callback(
            data.users.map((user) => {
              return { id: user.id, name: user.name };
            }),
          );
        });
    },
    shouldLoad: function (type) {
      return type.length > 2;
    },
  });
});
