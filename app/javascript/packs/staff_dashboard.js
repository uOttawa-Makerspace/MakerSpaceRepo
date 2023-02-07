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
function refreshTables() {
  let token = Array.from(
    document.querySelectorAll(`[data-user-id]`),
    (el) => el.dataset.userId
  ).join("");
  let url = "/staff_dashboard/refresh_tables?token=" + token;
  fetch(url)
    .then((response) => response.json())
    .then((data) => {
      console.log(data);
      if (!data.error) {
        if (document.getElementById("table-js-signed-out")) {
          document.getElementById("table-js-signed-out").innerHTML =
            data.signed_out;
        }
        if (document.getElementById("table-js-signed-in")) {
          document.getElementById("table-js-signed-in").innerHTML =
            data.signed_in;
        }
      }
    });
}
setInterval(refreshCapacity, 60000);
refreshCapacity();
setInterval(refreshTables, 15000);
