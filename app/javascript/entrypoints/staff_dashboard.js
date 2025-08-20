import DataTable from "datatables.net-bs5";
import "datatables.net-bs5/css/dataTables.bootstrap5.min.css";
import toastr from "toastr/toastr";

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

var displayedBefore = undefined;
function notifyNewUserLogin(users) {
  console.log("1");
  if (displayedBefore == undefined) {
    console.log("2");
    // first load, do not spam
    displayedBefore = new Array(users);
    // early out
    return;
  }
  // next load
  var displayNow = new Array(users);
  // get difference of displayed before and incoming
  displayNow.forEach((e) => {
    if (!displayedBefore.includes(e)) {
      toastr.success(e[2], "New User Sign-In");
    }
  });
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
        notifyNewUserLogin(data.users);
        // data.users.forEach(element => {
        //   toastr.success(element[2], 'New User Sign-In')
        // });
      }
    });
}

setInterval(refreshCapacity, 60000);
refreshCapacity();
setInterval(refreshTables, 5000);
refreshTables();
