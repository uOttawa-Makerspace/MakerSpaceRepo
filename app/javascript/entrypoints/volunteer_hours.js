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
              // Hours and minutes boxes combine into decimal hours for the hidden field.
              var hours = Number(form.querySelector("#hours").value);
              var minutes = Number(form.querySelector("#minutes").value);
              form.querySelector("#total_time_hidden").value =
                hours + minutes / 60.0;
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
