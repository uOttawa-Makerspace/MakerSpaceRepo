import TomSelect from "tom-select";

document.addEventListener("turbo:load", function () {
  // For "Send Print Failed Emails" form
  const printerSelect = document.querySelector("#printerNumberSelect");
  if (!printerSelect) return;

  let printerAssigns = {};
  fetch("/printers/last_user_assigned_to_printer", {
    headers: { Accept: "application/json" },
  })
    .then((response) => {
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      return response.json();
    })
    .then((json) => (printerAssigns = json))
    .catch((error) =>
      console.error("Could not load the last user of each printer", error),
    );

  new TomSelect("#printerNumberSelect", {
    items: [], // To clear default value
    onChange: function (printerId) {
      let userSelect = document.querySelector(
        "#user_dashboard_select",
      ).tomselect;

      // If a user is already typed in, don't replace
      if (userSelect.getValue()) {
        return;
      }
      // Find previous owner of this printer
      if (printerAssigns[printerId] && printerAssigns[printerId].username) {
        // and place into user dashboard select if it exists
        // NOTE the user dashboard script uses usernames
        userSelect.addOption({
          id: printerAssigns[printerId].username,
          name: printerAssigns[printerId].name,
        });
        userSelect.refreshOptions();
        userSelect.setValue(printerAssigns[printerId].username);
      }
    },
  });
});
