import TomSelect from "tom-select";
import Rails from "@rails/ujs";
import { Modal } from "bootstrap";

document.addEventListener("turbo:load", function () {
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
  let adminId; // To keep track of the current admin ID

  manageSpacesModal.addEventListener('show.bs.modal', function(event) {
    const button = event.relatedTarget; // Button that triggered the modal
    adminId = button.getAttribute('data-admin-id'); // Extract admin ID from data attribute
    const modalBody = manageSpacesModal.querySelector('.modal-body');
    
    // Clear previous contents and show loading status
    modalBody.innerHTML = '<p>Loading...</p>';

    // Fetch spaces associated with this admin
    fetch(`/admin/users/${adminId}/fetch_spaces`)
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP error, status = ${response.status}`);
        }
        return response.json();
      })
      .then(spaces => {
        modalBody.innerHTML = ''; // Clear the loading message
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
        modalBody.innerHTML = `<p>Error loading spaces: ${error.message}. Please try again.</p>`; // Handle errors more specifically
      });
  });

  // Save changes button handler
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
      // Handle success, maybe close the modal and show a success message
      console.log('Spaces updated successfully:', data);
      // Optionally close the modal
      const bootstrapModal = bootstrap.Modal.getInstance(manageSpacesModal);
      bootstrapModal.hide();
    })
    .catch(error => {
      console.error('Error updating spaces:', error);
    });
  });
});
