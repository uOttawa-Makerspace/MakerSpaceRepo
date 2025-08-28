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

// Testing Consent forms before they have been added

function getRandomInt(max) {
  return Math.floor(Math.random() * max);
}

const myModal = new bootstrap.Modal(document.getElementById("signinModal"), {
  keyboard: true,
});

var modalClicked = false;
const modal = document.getElementById("signinModal");
const progressBar = document.getElementById("outer-progress-bar");
const innerBar = document.getElementById("signin-progress-bar");
modal.addEventListener("click", function () {
  modalClicked = true;
  progressBar.classList.add("fading-progress-bar");
});

modal.addEventListener("hidden.bs.modal", function () {
  progressBar.classList.remove("fading-progress-bar");
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
  function notifyNewUserLogin(
    users,
    certification,
    has_membership,
    expiration_date,
    is_student,
  ) {
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
    modalClicked = false;
    innerBar.classList.add("moving-progress-bar");
    myModal.show();
    setTimeout(hideModal, 6000);

    // Setting Modal Text

    // Name
    document.getElementById("sign-in-username").innerText = e[0];
    // Link to Profile
    document.getElementById("sign-in-profile-link").innerHTML =
      '<a class="drop-username-cell fs-5" href="/' + e[2] + '">See Profile</a>';
    // Email
    document.getElementById("sign-in-email").innerText = e[1];
    // Membership Status
    if (has_membership) {
      document.getElementById("sign-in-membership").classList.add("glow");
      document.getElementById("sign-in-membership").classList.add("bg-success");
      document.getElementById("sign-in-membership").innerText =
        "Active until " + expiration_date;
    } else {
      document.getElementById("sign-in-membership").innerText =
        "No Active Membership";
      document.getElementById("sign-in-membership").classList.add("bg-danger");
    }
    // Is Community Member
    if (is_student) {
      document.getElementById("sign-in-student").innerText = "Student";
      document.getElementById("sign-in-student").classList.add("bg-success");
    } else {
      document.getElementById("sign-in-student").innerText = "Not Student";
      document.getElementById("sign-in-student").classList.add("bg-danger");
    }

    var consent = getRandomInt(2);
    if (consent == 0) {
      document.getElementById("sign-in-consent").innerText = "Signed";
      document.getElementById("sign-in-consent").classList.add("bg-success");
    } else {
      document.getElementById("sign-in-consent").innerText = "Unsigned";
      document.getElementById("sign-in-consent").classList.add("bg-danger");
    }

    // Displaying Certifications
    var certificationTrainings = certification[0][1];
    var result = "<h4>";

    certificationTrainings.forEach((e) => {
      result +=
        '<span class="badge text-bg-light text-black-50">' +
        e.name_en +
        "</span>  ";
    });
    result += "</h4>";
    document.getElementById("sign-in-certifications").innerHTML = result;

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
            data.expiration_date,
            data.is_student,
          );
        } else {
          console.error(data.error);
        }
      });
  }

  setInterval(refreshCapacity, 60000);
  refreshCapacity();
  setInterval(refreshTables, 5000);
  refreshTables();
});
