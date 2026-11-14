import TomSelect from "tom-select";
import { tomSelectOptions } from "../src/page_locale.js";

if (document.getElementById("kit_user_select")) {
  if (!document.getElementById("kit_user_select").tomselect) {
    new TomSelect(
      "#kit_user_select",
      tomSelectOptions(document, {
        searchField: ["name"],
        valueField: "id",
        labelField: "name",
        options: [],
        maxOptions: 5,
        searchOnKeyUp: true,
        load: function (type, callback) {
          if (type.length < 2) {
            return;
          } else {
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
          }
        },
        shouldLoad: function (type) {
          return type.length > 2;
        },
      }),
    );
  }
}
