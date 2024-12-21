import TomSelect from "tom-select";

const locker_specifier = new TomSelect("#locker_rental_locker_specifier", {
  searchPlaceholder: "Select locker...",
  // Hide options if not selected by locker_type
  render: {
    optgroup: function (data) {
      let optgroup = document.createElement("div");
      optgroup.className = "optgroup";
      optgroup.appendChild(data.options);
      return data.group.disabled == true ? null : optgroup;
    },
  },
});

// Add the disabled and hidden attribute to all optgroups
// except for selected type
function disableAllExcept(shortForm) {
  locker_specifier.input.querySelectorAll("optgroup").forEach((optgroup) => {
    optgroup.disabled = !(optgroup.label == shortForm);
    optgroup.hidden = !(optgroup.label == shortForm);
  });
  // re-render
  locker_specifier.sync();
}

const locker_type = new TomSelect("#locker_rental_locker_type_id", {
  onChange: (value) => {
    disableAllExcept(locker_type.options[value].text);
  },
});

locker_type.trigger("change", locker_type.getValue());
// window.locker_type = locker_type
// window.locker_specifier = locker_specifier
