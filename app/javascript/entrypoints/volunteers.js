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

  // 2. Datepickers
  flatpickr("#datepicker_start", {
    enableTime: true,
    time_24hr: true,
  });
  flatpickr("#datepicker_end", {
    enableTime: true,
    time_24hr: true,
  });

  // 3. My Stats Certification Quick Jump Search
  const trainingSelectEl = document.getElementById("training-search-select");
  if (trainingSelectEl && !trainingSelectEl.tomselect) {
    new TomSelect(trainingSelectEl, {
      create: false,
      maxItems: 1,
      allowEmptyOption: true,
      placeholder: "Search certification (e.g. Mill, 3D Printer, Laser)...",
      onChange: function (value) {
        if (!value) return;
        const target = document.getElementById(value);
        if (target) {
          // Switch to skills tab if not already active
          const skillsTabBtn = document.getElementById("skills-tab");
          if (skillsTabBtn && typeof bootstrap !== "undefined") {
            bootstrap.Tab.getOrCreateInstance(skillsTabBtn).show();
          }

          // Smooth scroll & temporary highlight
          target.scrollIntoView({ behavior: "smooth", block: "center" });
          const card = target.querySelector(".card") || target;
          card.classList.add("border-primary", "shadow");
          setTimeout(() => {
            card.classList.remove("border-primary", "shadow");
          }, 2000);
        }
      },
    });
  }
});
