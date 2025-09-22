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

        let url = "/staff_dashboard/populate_users?search=" + type;
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
          return `<div class="ts-item">
          <span>${escape(item.name)}</span>
        </div>`;
        },
        option: (item, escape) => {
          return `<div class="ts-option">
          <strong>${escape(item.name)}</strong>
          <small class="text-muted ms-2">@${escape(item.id)}</small>
        </div>`;
        },
      },
    });
  });

  let form = document.getElementById("sign_in_user_fastsearch");
  if (form) {
    form.onsubmit = function () {
      document.getElementById("sign_in_user_fastsearch_username").value = [
        document.getElementById("user_dashboard_select").value,
      ];
      form.submit();
    };
  }
});
