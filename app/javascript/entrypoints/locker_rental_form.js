import TomSelect from "tom-select";

document.addEventListener("turbo:load", function () {
  // Search bar to pick an available locker
  document
    .querySelectorAll("#locker_rental_locker_id, #locker_id")
    .forEach((el) => {
      if (!el.tomselect) {
        new TomSelect(el, {
          create: false,
          maxItems: 1,
          // Tell TomSelect to use Bootstrap's classes
          input_class: "form-select",
          invalid_cls: "is-invalid",
          render: {
            option: function (data, escape) {
              let size = escape(data.size);
              let text = escape(data.text);
              let staffOnly = data.staffOnly == "true" ? " - Staff only" : "";
              return `<div>Locker ${text} - Size ${size}${staffOnly}</div>`;
            },
            item: function (data, escape) {
              let size = escape(data.size);
              let text = escape(data.text);
              let staffOnly = data.staffOnly == "true" ? " - Staff only" : "";
              return `<div>Locker ${text} - Size ${size}${staffOnly}</div>`;
            },
          },
        });
      }
    });

  // Search bar to pick a user to assign the locker to
  const userSelect = document.querySelector("#locker_rental_rented_by_id");
  if (userSelect && !userSelect.tomselect) {
    new TomSelect(userSelect, {
      maxItems: 1,
      valueField: "value",
      labelField: "text",
      searchField: ["text", "role"],
      // Tell TomSelect to use Bootstrap's classes
      input_class: "form-select",
      invalid_cls: "is-invalid",
      render: {
        option: function (data, escape) {
          let role = data.role
            ? `<span class="badge text-bg-primary ms-2">${escape(data.role)}</span>`
            : "";
          return `<div>${escape(data.text)}${role}</div>`;
        },
        item: function (data, escape) {
          let role = data.role
            ? `<span class="badge text-bg-primary ms-2">${escape(data.role)}</span>`
            : "";
          return `<div>${escape(data.text)}${role}</div>`;
        },
      },
    });
  }
});
