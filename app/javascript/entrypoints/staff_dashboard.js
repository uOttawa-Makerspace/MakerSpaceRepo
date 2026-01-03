import DataTable from "datatables.net-bs5";
import { Modal } from "bootstrap";
import { staffDashboardChannelConnection } from "../channels/staff_dashboard_channel";

var modalClicked = false;
const modal = document.getElementById("signinModal");
const notifyModal = new Modal(modal);

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
  if (form) {
    form.onsubmit = function () {
      document.getElementById("sign_in_user_fastsearch_username").value = [
        document.getElementById("user_dashboard_select").value,
      ];
      form.submit();
    };
  }

  var form2 = document.getElementById("search_user_fastsearch");
  if (form2) {
    form2.onsubmit = function () {
      document.getElementById("search_user_fastsearch_username").value =
        document.getElementById("user_dashboard_select").value;
      form2.submit();
    };
  }

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
      notifyModal.hide();
    }
  }

  function disableNotificationModal() {
    // Is the switch disabled
    let popupEnabledCheck = document.querySelector("input#popup_enabled");
    if (popupEnabledCheck && !popupEnabledCheck.checked) {
      return true;
    }

    // Is user currently searching something
    let userSearchBar = document.querySelector("#user_dashboard_select");
    if (
      userSearchBar &&
      userSearchBar.tomselect &&
      userSearchBar.tomselect.isOpen &&
      userSearchBar.tomselect.inputValue() != ""
    ) {
      return true;
    }

    return false;
  }

  var displayBefore = undefined;
  function notifyNewUserLogin(
    users,
    certification,
    has_membership,
    expiration_date,
    is_student,
    signed_sheet,
  ) {
    if (disableNotificationModal()) {
      return;
    }

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
    notifyModal.show();
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
      document.getElementById("no-membership").style.display = "none";
      document.getElementById("has-membership").style.display = "block";
      document.getElementById("sign-in-membership").innerText =
        "Active until " + expiration_date;
    } else {
      document.getElementById("has-membership").style.display = "none";
      document.getElementById("no-membership").style.display = "block";
    }
    // Is Community Member
    if (is_student) {
      document.getElementById("not-student").style.display = "none";
      document.getElementById("is-student").style.display = "block";
    } else {
      document.getElementById("is-student").style.display = "none";
      document.getElementById("not-student").style.display = "block";
    }

    if (signed_sheet) {
      document.getElementById("unsigned-consent-form").style.display = "none";
      document.getElementById("signed-consent-form").style.display = "block";
    } else {
      document.getElementById("signed-consent-form").style.display = "none";
      document.getElementById("unsigned-consent-form").style.display = "block";
    }

    // Displaying Certifications
    if (certification[0] != null) {
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
    } else {
      document.getElementById("sign-in-certifications").innerHTML = "";
    }
    // Updating previous user signin list
    displayBefore = displayNow;
  }

  refreshCapacity();

  function userTapIn(user) {
    if (disableNotificationModal()) {
      return;
    }

    innerBar.classList.add("moving-progress-bar");

    document.getElementById("sign-in-username").innerText = user.username;
    document.getElementById("sign-in-profile-link").href = user.username;
    // '<a class="drop-username-cell fs-5" href="/' + e[2] + '">See Profile</a>';
    document.getElementById("sign-in-email").innerText = user.email;
    document.getElementById("no-membership").style.display = user.membership
      ? "none"
      : "block";
    document.getElementById("has-membership").style.display = user.membership
      ? "block"
      : "none";
    document.getElementById("sign-in-membership").innerText =
      "Active until " + user.expiration_date;

    document.getElementById("not-student").style.display = !user.is_student
      ? "block"
      : "none";
    document.getElementById("is-student").style.display = user.is_student
      ? "block"
      : "none";
    document.getElementById("unsigned-consent-form").style.display =
      user.signed_sheet ? "none" : "block";
    document.getElementById("signed-consent-form").style.display =
      !user.signed_sheet ? "none" : "block";

    console.log(user.certification);
    let certificationsList = user.certification.map(
      (name_en) =>
        `<span class="badge text-bg-light text-black-50">${name_en}</span>`,
    );
    console.log(certificationsList);
    document.getElementById("sign-in-certifications").innerHTML =
      `<span class='.fs-4'>${certificationsList.join("")}</span>`;

    const dt = new DataTable(document.querySelector("#signed-in-table"));
    // Reflow table after table gets updated
    dt.draw();

    notifyModal.show();
    setTimeout(hideModal, 6000);
  }

  // Start web socket connection
  staffDashboardChannelConnection((data) => {
    //console.log(data);
    if (data.add_user) {
      userTapIn(data.add_user);
    }
  });
});
