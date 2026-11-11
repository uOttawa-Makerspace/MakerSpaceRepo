// Hours and minutes boxes combine into decimal hours for the hidden field. An edit form whose boxes are
// untouched keeps the stored total, which the minutes box can only show to the nearest minute.
function combineTotal(form) {
  var hours = form.querySelector("#hours");
  var minutes = form.querySelector("#minutes");
  var total = form.querySelector("#total_time_hidden");
  var untouched =
    total.value !== "" &&
    hours.value === hours.defaultValue &&
    minutes.value === minutes.defaultValue;
  if (!untouched) {
    total.value = Number(hours.value) + Number(minutes.value) / 60.0;
  }
}

document.addEventListener("turbo:load", function () {
  window.addEventListener(
    "load",
    function () {
      var forms = document.getElementsByClassName("needs-validation");
      Array.prototype.forEach.call(forms, function (form) {
        form.addEventListener(
          "submit",
          function (event) {
            if (form.checkValidity() === false) {
              event.preventDefault();
              event.stopPropagation();
            } else {
              combineTotal(form);
            }
            form.classList.add("was-validated");
          },
          false,
        );
      });
    },
    false,
  );
});
