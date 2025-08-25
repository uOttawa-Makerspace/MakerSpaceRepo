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
    myModal.hide();
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
    myModal.show();
    setTimeout(hideModal, 4000);
    console.log(e);

    // Setting Modal Text
    document.getElementById("signinModalHeader").innerText = e[0];
    document.getElementById("signinProfileLink").innerHTML =
      '<a class="drop-username-cell" href="/' + e[2] + '">See Profile</a>';
    document.getElementById("signinEmail").innerText = e[1];
    if (has_membership) {
      document.getElementById("signinMembership").innerText = "Has Membership";
    } else {
      document.getElementById("signinMembership").innerText = "No Membership";
    }
    var certificationTrainings = certification[0][1];
    var trainingString = "";
    certificationTrainings.forEach((e) => {
      trainingString = trainingString + "  |  " + e.name_en;
    });
    document.getElementById("signinCertifications").innerHTML =
      '<p id="signinCertification">' + trainingString + "</p>";
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
