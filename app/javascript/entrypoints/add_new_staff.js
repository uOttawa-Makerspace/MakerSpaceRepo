import { onEveryPageLoad } from "../src/on_page.js";
import { reportFailure, requestJson } from "../src/request_error";
import { tomSelectFor } from "../src/tom_select.js";

onEveryPageLoad(() => {
  const el = document.getElementById("new_staff_select");
  if (!el) return;
  tomSelectFor(el, {
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
      requestJson(
        `/repositories/populate_users?search=${encodeURIComponent(query)}`,
        undefined,
        { requireBody: true },
      )
        .then((data) =>
          callback(
            data.users.map((u) => ({
              id: u.username, // this is what will be submitted
              name: u.name,
            })),
          ),
        )
        .catch((error) => {
          reportFailure(error);
          callback();
        });
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
});
