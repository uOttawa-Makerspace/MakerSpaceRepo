import TomSelect from "tom-select";

document.addEventListener("turbo:load", function () {
  const all_selects = [
    "#ultimaker2p",
    "#ultimaker3",
    "#replicator2",
    "#dremel",
  ];
  for (let i = 0; i < all_selects.length; i++) {
    try {
      new TomSelect(all_selects[i], {});
    } catch (e) {} // nothing to catch O_O
  }

  // For "Send Print Failed Emails" form
  try {
    let printerAssigns = {};
    fetch("/printers/last_user_assigned_to_printer")
      .then((response) => response.json())
      .then((json) => (printerAssigns = json));
    //let printerAssigns = await response.json()
    console.log(printerAssigns);

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
  } catch (e) {
    console.log(e);
  }
});
