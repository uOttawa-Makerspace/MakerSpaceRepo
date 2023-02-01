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
      closeAfterSelect: true,
    });
  }
}
if (document.getElementById("staff_id")) {
  if (!document.getElementById("staff_id").tomselect) {
    new TomSelect("#staff_id", {
      plugins: ["remove_button"],
      maxItems: null,
      closeAfterSelect: true,
    });
  }
}
if (document.getElementById("remove_staff_id")) {
  if (!document.getElementById("remove_staff_id").tomselect) {
    new TomSelect("#remove_staff_id", {
      plugins: ["remove_button"],
      maxItems: null,
      closeAfterSelect: true,
    });
  }
}
if (document.getElementById("remove_volunteer_id")) {
  if (!document.getElementById("remove_volunteer_id").tomselect) {
    new TomSelect("#remove_volunteer_id", {
      plugins: ["remove_button"],
      maxItems: null,
      closeAfterSelect: true,
    });
  }
}
let hider = document.getElementById("task-hider");
if (hider) {
  var completedRows = document.querySelectorAll('tr[completed="completed"]');
  hider.addEventListener("click", () => {
    completedRows.forEach((row) => {
      row.classList.toggle("d-none");
    });
    hider.innerHTML =
      hider.innerHTML == "Hide Completed Task"
        ? "Show Completed Task"
        : "Hide Completed Task";
  });
}
