import TomSelect from "tom-select";
document.addEventListener("turbo:load", function () {
  if (document.getElementById("user_id")) {
    if (!document.getElementById("user_id").tomselect) {
      new TomSelect("#user_id", {
        placeholder: "Select a user",
        maxItems: 1,
        plugins: ["remove_button"],
      });
    }
  }

  if (document.getElementById("task_certifications")) {
    if (!document.getElementById("task_certifications").tomselect) {
      new TomSelect("#task_certifications", {
        plugins: ["remove_button"],
        maxItems: null,
      });
    }
  }
  if (document.getElementById("volunteer_id")) {
    if (!document.getElementById("volunteer_id").tomselect) {
      new TomSelect("#volunteer_id", {
        plugins: ["remove_button"],
        maxItems: null,
      });
    }
  }
  if (document.getElementById("staff_id")) {
    if (!document.getElementById("staff_id").tomselect) {
      new TomSelect("#staff_id", {
        maxItems: 1,
      });
    }
  }
});

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
          }
          form.classList.add("was-validated");
        },
        false
      );
    });
  },
  false
);
