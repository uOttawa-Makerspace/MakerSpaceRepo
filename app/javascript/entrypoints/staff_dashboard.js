import DataTable from "datatables.net-bs5";
import "datatables.net-bs5/css/dataTables.bootstrap5.min.css";
import toastr from "toastr/toastr";
import * as bootstrap from "bootstrap";

toastr.options = {
  closeButton: true,
  debug: false,
  newestOnTop: false,
  progressBar: true,
  positionClass: "toast-bottom-full-width",
  preventDuplicates: false,
  showDuration: "300",
  hideDuration: "1000",
  timeOut: "5000",
  extendedTimeOut: "1000",
  showEasing: "swing",
  hideEasing: "linear",
  showMethod: "fadeIn",
  hideMethod: "fadeOut",
  escapeHTML: true,
};

const myModal = new bootstrap.Modal(document.getElementById("signinModal"), {
  keyboard: true,
});

var modalClicked = false;
const modal = document.getElementById("signinModal");
modal.addEventListener("click", function () {
  modalClicked = true;
  const progressBar = document.getElementById("outer-progress-bar");
  progressBar.classList.add("fading-progress-bar");
});

document.addEventListener("turbo:load", function () {
  var form = document.getElementById("sign_in_user_fastsearch");
  form.onsubmit = function () {
    document.getElementById("sign_in_user_fastsearch_username").value = [
      document.getElementById("user_dashboard_select").value,
    ];
    form.submit();
  };

  var form2 = document.getElementById("search_user_fastsearch");
  form2.onsubmit = function () {
    document.getElementById("search_user_fastsearch_username").value =
      document.getElementById("user_dashboard_select").value;
    form2.submit();
  };

  document
    .querySelector(".form-control-input-excel")
    .addEventListener("change", function (e) {
      var fileName = document.getElementById("excel-input").files[0].name;
      var nextSibling = e.target.nextElementSibling;
      nextSibling.innerText = fileName;
    });

  function refreshCapacity() {
    let url = "/staff_dashboard/refresh_capacity";
    fetch(url)
      .then((response) => response.text())
      .then((data) => {
        if (document.getElementsByClassName("max_capacity_alert")[0])
          document.getElementsByClassName("max_capacity_alert")[0].innerHTML =
            data;
      });
  }

  function hideModal() {
    if (!modalClicked) {
      myModal.hide();
    }
  }

  var displayBefore = undefined;
  function notifyNewUserLogin(users, certification, has_membership) {
    var displayNow = [];
    if (displayBefore == undefined) {
      displayNow = users;
    } else {
      users.forEach((e) => {
        if (!displayBefore.includes(e)) {
          displayNow.push(e);
        }
      });
    }
    var e = displayNow[0];

    // Display/Refresh Modal
    const modalElement = document.getElementById("signinModal");
    myModal.show();
    setTimeout(hideModal, 4000);

    // Setting Modal Text

    // Name
    document.getElementById("signinModalHeader").innerText = e[0];
    // Link to Profile
    document.getElementById("signinProfileLink").innerHTML =
      '<a class="drop-username-cell" href="/' + e[2] + '">See Profile</a>';
    // Email
    document.getElementById("signinEmail").innerText = e[1];
    // Membership Status
    if (has_membership) {
      document.getElementById("signinMembership").innerText = "Has Membership";
    } else {
      document.getElementById("signinMembership").innerText = "No Membership";
    }

    // Displaying Certifications
    var trainingString = "";
    if (certification[0] == null) {
      trainingString = "No Certifications";
    } else {
      var certificationTrainings = certification[0][1];
      console.log(certification[0][1]);

      certificationTrainings.forEach((e) => {
        if (trainingString == "") {
          trainingString = trainingString + e.name_en;
        } else {
          trainingString = trainingString + "  |  " + e.name_en;
        }
      });
    }

    document.getElementById("signinCertifications").innerHTML =
      '<p id="signinCertification">' + trainingString + "</p>";

    // Updating previous user signin list
    displayBefore = displayNow;
  }

  function refreshTables() {
    let token = Array.from(
      document.querySelectorAll(`[data-user-id]`),
      (el) => el.dataset.userId,
    ).join("");
    let url = "/staff_dashboard/refresh_tables?token=" + token;
    fetch(url)
      .then((response) => response.json())
      .then((data) => {
        if (!data.error) {
          if (document.getElementById("table-js-signed-out")) {
            document.getElementById("table-js-signed-out").innerHTML =
              data.signed_out;
          }
          if (document.getElementById("table-js-signed-in")) {
            document.getElementById("table-js-signed-in").innerHTML =
              data.signed_in;
          }
          notifyNewUserLogin(
            data.users,
            data.certification,
            data.has_membership,
          );
        } else {
          console.error(data.error);
        }
      });
  }

  setInterval(refreshCapacity, 60000);
  refreshCapacity();
  setInterval(refreshTables, 15000);
  refreshTables();
});
