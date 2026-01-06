import TomSelect from "tom-select";
import "flatpickr";

document.addEventListener("turbo:load", function () {
  if (document.getElementById("user_select")) {
    if (!document.getElementById("user_select").tomselect) {
      new TomSelect("#user_select", {
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
            let url = "/volunteers/populate_users?search=" + type;
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
      });
    }
  }
  flatpickr("#datepicker_start", {
    enableTime: true,
    time_24hr: true,
  });
  flatpickr("#datepicker_end", {
    enableTime: true,
    time_24hr: true,
  });
});
