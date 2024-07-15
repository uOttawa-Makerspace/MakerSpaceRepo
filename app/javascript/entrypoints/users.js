import TomSelect from "tom-select";
import Rails from "@rails/ujs";

document.addEventListener("turbo:load", function () {
  // Find hash and manually click on load
  // this only finds links within the #myTab element
  // because having random links be clicked via a hash is a security nightmare
  const profileTablist = document.getElementById("myTab");
  if (profileTablist) {
    [...profileTablist.querySelectorAll("a")].forEach((item) => {
      if (item.getAttribute("href") == window.location.hash) item.click();
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
  }
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

        Rails.ajax({
          url: url,
          type: "PATCH",
          data: formData,
          success: function (data) {
            document.getElementById(e.target.id + "_show").style.display =
              "none";
            document.getElementById(e.target.id + "_hide").style.display =
              "block";
          },
          error: function (data) {
            alert(
              "Something went wrong when uploading the file, please try again later"
            );
          },
        });
      } else {
        alert("Please attach a pdf file only");
      }
    });
  });
});

document.addEventListener('DOMContentLoaded', function() {
  const manageSpacesModal = document.getElementById('manageSpacesModal');
  let adminId;
  manageSpacesModal.addEventListener('show.bs.modal', function(event) {
    const button = event.relatedTarget;
    adminId = button.getAttribute('data-admin-id');
    const modalBody = manageSpacesModal.querySelector('.modal-body');
    
    modalBody.innerHTML = '<p>Loading...</p>';

    fetch(`/admin/users/${adminId}/fetch_spaces`)
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP error, status = ${response.status}`);
        }
        return response.json();
      })
      .then(spaces => {
        modalBody.innerHTML = '';
        spaces.forEach(space => {
          const isChecked = space.is_assigned ? 'checked' : '';
          const checkboxHTML = `
            <div class="form-check">
              <input class="form-check-input" type="checkbox" value="${space.id}" id="space_${space.id}" ${isChecked}>
              <label class="form-check-label" for="space_${space.id}">
                ${space.name}
              </label>
            </div>
          `;
          modalBody.innerHTML += checkboxHTML;
        });
      })
      .catch(error => {
        console.error('Error loading spaces:', error);
        modalBody.innerHTML = `<p>Error loading spaces: ${error.message}. Please try again.</p>`;
      });
  });


  document.getElementById('saveSpaceChangesButton').addEventListener('click', function() {
    const checkedBoxes = manageSpacesModal.querySelectorAll('.form-check-input:checked');
    const spaceIds = Array.from(checkedBoxes).map(cb => cb.value);

    fetch(`/admin/users/${adminId}/update_spaces`, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
      },
      body: JSON.stringify({ space_ids: spaceIds })
    })
    .then(response => {
      if (!response.ok) {
        throw new Error(`HTTP error, status = ${response.status}`);
      }
      return response.json();
    })
    .then(data => {    

      location.reload();
     

    })
    .catch(error => {
      console.error('Error updating spaces:', error);
    });
  });
});

document.addEventListener('DOMContentLoaded', function() {
 
  document.getElementById('select-all').addEventListener('click', function(event) {
    const checked = event.target.checked;
    document.querySelectorAll('.select-user').forEach(function(checkbox) {
      checkbox.checked = checked;
    });
  });

  document.getElementById('change-button').addEventListener('click', function(event) {
    console.log('Form submit event'); // Debugging line to check if submit event is triggered
    const selectedUserIds = Array.from(document.querySelectorAll('.select-user:checked')).map(cb => cb.value);
    console.log('Selected user IDs:', selectedUserIds); // Debugging line to check the selected user IDs
    document.getElementById('user_ids_field').value = selectedUserIds.join(',');
  });
});

//Staff

const manageSpacesModal = document.getElementById('manageSpacesModal');
  let staffId;

  manageSpacesModal.addEventListener('show.bs.modal', function(event) {
    const button = event.relatedTarget;
    staffId = button.getAttribute('data-staff-id');
    const modalBody = manageSpacesModal.querySelector('.modal-body');
    
    modalBody.innerHTML = '<p>Loading...</p>';

    fetch(`/admin/users/${staffId}/fetch_spaces`)
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP error, status = ${response.status}`);
        }
        return response.json();
      })
      .then(spaces => {
        modalBody.innerHTML = '';
        spaces.forEach(space => {
          const isChecked = space.is_assigned ? 'checked' : '';
          const checkboxHTML = `
            <div class="form-check">
              <input class="form-check-input" type="checkbox" value="${space.id}" id="space_${space.id}" ${isChecked}>
              <label class="form-check-label" for="space_${space.id}">
                ${space.name}
              </label>
            </div>
          `;
          modalBody.innerHTML += checkboxHTML;
        });
      })
      .catch(error => {
        console.error('Error loading spaces:', error);
        modalBody.innerHTML = `<p>Error loading spaces: ${error.message}. Please try again.</p>`;
      });
  });

  document.getElementById('saveSpaceChangesButton').addEventListener('click', function() {
    const checkedBoxes = manageSpacesModal.querySelectorAll('.form-check-input:checked');
    const spaceIds = Array.from(checkedBoxes).map(cb => cb.value);

    fetch(`/admin/users/${staffId}/update_spaces`, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
      },
      body: JSON.stringify({ space_ids: spaceIds })
    })
    .then(response => {
      if (!response.ok) {
        throw new Error(`HTTP error, status = ${response.status}`);
      }
      return response.json();
    })
    .then(data => {    
      location.reload();
     

    })
    .catch(error => {
      console.error('Error updating spaces:', error);
    });
  });

  document.addEventListener('DOMContentLoaded', function() {
  
  
    // Select/Deselect all checkboxes for staff
    document.getElementById('select-all-staff').addEventListener('click', function(event) {
      const checked = event.target.checked;
      document.querySelectorAll('.select-user-staff').forEach(function(checkbox) {
        checkbox.checked = checked;
      });
    });
  
    // Update the hidden field with selected user IDs when the button is clicked for staff
    document.getElementById('change-button-staff').addEventListener('click', function(event) {
      console.log('Form submit event for staff'); // Debugging line to check if submit event is triggered
      const selectedUserIds = Array.from(document.querySelectorAll('.select-user-staff:checked')).map(cb => cb.value);
      console.log('Selected user IDs for staff:', selectedUserIds); // Debugging line to check the selected user IDs
      document.getElementById('user_ids_field_staff').value = selectedUserIds.join(',');
    })});
