document.addEventListener("turbo:load", function () {
  window.addEventListener(
    "load",
    function () {
      var forms = document.getElementsByClassName("needs-validation");
      var validation = Array.prototype.filter.call(forms, function (form) {
        form.addEventListener(
          "submit",
          function (event) {
            if (form.checkValidity() === false) {
              event.preventDefault();
              event.stopPropagation();
            } else {
              var total_time_hidden =
                document.getElementById("total_time_hidden");
              var hour = document.getElementById("hour").value;
              var minutes = document.getElementById("minutes").value;
              var total_time = hour + minutes / 60.0;
              total_time_hidden.value = total_time;
            }
            form.classList.add("was-validated");
          },
          false
        );
      });
    },
    false
  );
});
