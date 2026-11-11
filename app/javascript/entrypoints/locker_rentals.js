import "datatables.net-bs5/css/dataTables.bootstrap5.min.css";
import TomSelect from "tom-select";

document.addEventListener("turbo:load", () => {
  if (document.querySelector("#locker_rental_preferred_locker_id")) {
    new TomSelect("#locker_rental_preferred_locker_id", {
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

document.addEventListener("turbo:load", () => {
  // For user facing locker request form
  let requestedAsSelect = document.getElementById("locker_rental_requested_as");
  let repoSelect = document.getElementById("repo-select");
  if (requestedAsSelect && repoSelect) {
    requestedAsSelect.addEventListener("change", function (evt) {
      if (evt.target.value === "student") {
        repoSelect.hidden = false;
        repoSelect.removeAttribute("disabled");
      } else {
        repoSelect.hidden = true;
        repoSelect.setAttribute("disabled", "");
      }
    });
    requestedAsSelect.dispatchEvent(new Event("change"));
  }
});
