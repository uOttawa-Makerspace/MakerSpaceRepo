import TomSelect from "tom-select";

let prev_anchor = "";
document.addEventListener("turbo:submit-start", function () {
  prev_anchor = window.location.hash;
});

document.addEventListener("turbo:load", function () {
  if (prev_anchor) {
    window.location.hash = prev_anchor;
    prev_anchor = "";
  }
  // Find hash and manually click on load
  // this only finds links within the #myTab element
  // because having random links be clicked via a hash is a security nightmare
  const profileTablist = document.getElementById("myTab");
  if (profileTablist) {
    // Find admin tab, exists if user is an admin
    const adminTab = profileTablist.querySelector("#admin-tab");

    if (adminTab) {
      // Get all admin sub tabs
      const adminTablist = document
        .getElementById("adminTabPane")
        .querySelectorAll(".nav-link");
      adminTablist.forEach((el) => {
        // on click, change hash
        el.addEventListener("click", (ev) => {
          window.location.hash = el.getAttribute("href");
        });

        // If hash linking to this tab, click
        if (window.location.hash == el.getAttribute("href")) {
          el.click();
        }
      });
    }

    profileTablist.querySelectorAll(".nav-link").forEach((el) => {
      // Add the hash on click on any outer tab
      el.addEventListener("click", (ev) => {
        window.location.hash = el.getAttribute("href");
      });
      // special case for admin.
      if (window.location.hash.startsWith("#admin-")) {
        // This is an admin pane
        if (adminTab) {
          // preserve this hash
          let this_hash = window.location.hash;
          adminTab.click();
          window.location.hash = this_hash;
        }
      } else if (el.getAttribute("href") == window.location.hash) {
        el.click();
      }
    });
  }

  const elements = document.querySelectorAll("[data-show], [data-hide]");
  for (let i = 0; i < elements.length; i++) {
    elements[i].addEventListener("change", function () {
      const selector =
        this.getAttribute("data-show") || this.getAttribute("data-hide");
      const show = this.getAttribute("data-show") != null;
      const hide = this.getAttribute("data-hide") != null;
      const checked = this.checked;

      if (checked && (show || hide)) {
        document.querySelector(selector).style.display = show
          ? "block"
          : "none";
        document.querySelector(selector).disabled = !show;
      }
    });

    if (elements[i].checked) {
      elements[i].dispatchEvent(new Event("change"));
    }
  }

  const programSelect = document.getElementById("user_program");
  if (programSelect && !programSelect.tomselect) {
    new TomSelect(programSelect, {
      maxItems: 1,
      maxOptions: null,
      searchOnKeyUp: true,
    });
    // this is a non-live NodeList, we store it for later use
    const optgroups = Array.from(programSelect.querySelectorAll("optgroup"));
    const facultySelect = document.getElementById("user_faculty");
    if (facultySelect) {
      facultySelect.addEventListener("change", function () {
        // https://tom-select.js.org/docs/api/
        programSelect.querySelectorAll("optgroup").forEach((e) => e.remove());
        // Add allowed programs
        let target_label = facultySelect.value;
        for (let i = 0; i < optgroups.length; i++) {
          let option = optgroups[i];
          if (option.getAttribute("label") == target_label)
            programSelect.appendChild(option);
        }

        programSelect.tomselect.clear();
        programSelect.tomselect.clearOptions();
        programSelect.tomselect.sync();
      });
    }
  }

  const staffRoleButtons = document.querySelectorAll(".role-button");
  const staffSpaceChanger = document.getElementById("staff-space-changer");
  if (staffRoleButtons) {
    staffRoleButtons.forEach((button) => {
      button.addEventListener("click", (e) => {
        if (e.target.value === "regular_user") {
          staffSpaceChanger.style.display = "none";
        } else {
          staffSpaceChanger.style.display = "block";
        }
      });
    });
  }

  const fileInputs = document.querySelectorAll(".key-cert-file");
  fileInputs.forEach((fileInput) => {
    fileInput.addEventListener("change", (e) => {
      const form = document.getElementById(e.target.id + "_form");
      const uploadedFile = fileInput.files[0];
      const url = form.getAttribute("action");
      const authToken = form[1].value;

      if (uploadedFile && uploadedFile.type === "application/pdf") {
        const formData = new FormData();
        formData.append(e.target.id, uploadedFile);
        formData.append("authenticity_token", authToken);

        fetch(url, {
          method: "PATCH",
          headers: {
            Accept: "application/json",
            //'Content-Type': 'application/json',
          },
          body: formData,
        })
          .then((response) => {
            if (response.ok) {
              document.getElementById(e.target.id + "_show").style.display =
                "none";
              document.getElementById(e.target.id + "_hide").style.display =
                "block";
            }
          })
          .catch((err) => {
            console.error(err);
            alert("Something went wrong uploading");
          });
      } else {
        alert("Please attach a pdf file only");
      }
    });
  });

  // For the select boxes in admin/users/manage_roles
  document.querySelectorAll(".role-space-select").forEach((i) => {
    new TomSelect(i, {
      plugins: {
        checkbox_options: {
          checkedClassNames: ["ts-checked"],
          uncheckedClassNames: ["ts-unchecked"],
        },
        remove_button: { title: "Remove space" },
      },
    });
  });

  document.querySelectorAll("input.set-user-space-button").forEach((i) => {
    i.addEventListener("change", (event) => {
      // Get total space list
      let space_list = [
        ...i.parentElement.querySelectorAll("input.set-user-space-button"),
      ].reduce(function (result, element) {
        if (element.checked) {
          result.push(element.dataset.spaceId);
        }
        return result;
      }, []);
      let body = { user_ids: [i.dataset.userId], spaces: {} };
      body["spaces"][i.dataset.userId] = space_list;
      fetch("/admin/users/set_role/", {
        method: "PATCH",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      });
    });
  });
});
