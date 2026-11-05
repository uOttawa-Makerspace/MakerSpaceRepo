import TomSelect from "tom-select";
// This is also used in printers/_send_print_failed_form
// and in locker_rentals/new
// make sure you don't break that too
document.addEventListener("turbo:load", function () {
  document.querySelectorAll("[data-user-search-bar]").forEach((el) => {
    if (el.tomsselect) return;
    new TomSelect(el, {
      // https://github.com/orchidjs/tom-select/issues/78#issuecomment-837319408
      // Disable local search
      searchField: [],
      // Sends user ID
      valueField: "id",
      labelField: "name",
      options: [],
      plugins: el.multiple ? ["remove_button"] : [],
      searchPlaceholder: "Choose User...",
      searchOnKeyUp: true,
      load: function (type, callback) {
        if (type.length < 2) {
          return callback();
        }

        let url = "/users/search?search=" + type;
        fetch(url)
          .then((response) => response.json())
          .then((data) => {
            // Clear leftover search results
            this.clearOptions();
            callback(
              data.users.map((user) => {
                return { id: user.username, name: user.name };
              }),
            );
          })
          .catch(() => {
            callback();
          });
      },
      shouldLoad: function (type) {
        return type.length > 2;
      },
      render: {
        item: (item, escape) => {
          const link = document.createElement("a");
          link.className = "ts-item";
          link.innerText = item.name ? escape(item.name) : escape(item.id);
          link.href = `/${escape(item.id)}`;
          link.setAttribute("target", "_blank");
          link.addEventListener("click", function (evt) {
            evt.stopPropagation();
          });
          return link;
        },
        option: (item, escape) => {
          const div = document.createElement("div");
          div.className = "ts-option";
          const strong = document.createElement("strong");
          strong.innerText = item.name ? escape(item.name) : escape(item.id);

          const username = document.createElement("a");
          username.className = "ms-2";
          username.innerText = `@${escape(item.id)}`;
          username.href = `/${escape(item.id)}`;
          username.setAttribute("target", "_blank");

          username.addEventListener("click", function (evt) {
            evt.stopPropagation();
          });

          div.append(strong);
          div.append(username);
          return div;
        },
      },
    });
  });
  // staff_dashboard/_search: the user picker sits outside the Sign In (PUT) and
  // View (GET) forms; the submitted form carries the picked username.
  [
    ["sign_in_user_fastsearch", "sign_in_user_fastsearch_username"],
    ["search_user_fastsearch", "search_user_fastsearch_username"],
  ].forEach(([formId, inputId]) => {
    const form = document.getElementById(formId);
    if (!form) return;
    form.onsubmit = () => {
      document.getElementById(inputId).value =
        document.getElementById("user_dashboard_select")?.value ?? "";
    };
  });
});
