import TomSelect from "tom-select";

const el = document.getElementById("new_staff_select");
if (el && !el.tomselect) {
  const ts = new TomSelect(el, {
    valueField: "id", // what gets submitted to Rails
    labelField: "name", // what gets displayed
    searchField: "name",
    options: [],
    maxItems: null, // or a number if you want to limit selections
    hideSelected: true,
    plugins: ["remove_button"], // adds the "x" to remove items
    closeAfterSelect: false,

    load(query, callback) {
      if (query.length < 2) return callback();
      fetch(`/repositories/populate_users?search=${encodeURIComponent(query)}`)
        .then((r) => r.json())
        .then((data) =>
          callback(
            data.users.map((u) => ({
              id: u.username, // this is what will be submitted
              name: u.name,
            })),
          ),
        )
        .catch(() => callback());
    },
    shouldLoad: (query) => query.length >= 2,

    render: {
      item: (item, escape) => {
        return `<div class="ts-item">
          <a class="ms-1" href="/${escape(item.id)}">${escape(item.name)}</a>
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
}
