[...document.getElementsByClassName("pp-status-button")].forEach(function (
  element
) {
  if (element.innerHTML === "Revoked") {
    element.classList.add("btn-danger");
  } else if (element.innerHTML === "Awarded") {
    element.classList.add("btn-success");
  } else {
    element.classList.add("btn-warning");
  }
});
if (document.getElementById("badge_requirements")) {
  if (!document.getElementById("badge_requirements").tomselect) {
    new TomSelect("#badge_requirements", {
      plugins: ["remove_button"],
      maxItems: null,
    });
  }
}
let form =
  document.getElementById("new_proficient_project") ||
  document.getElementsByClassName("edit_proficient_project")[0];
if (form) {
  form.addEventListener("submit", (e) => {
    let images = document.getElementById("images_");
    let image_feedback = document.createElement("div");
    image_feedback.classList.add("text-center");
    let uploaded_images = document.getElementsByClassName("image-item").length;
    let total_images = uploaded_images + images.files.length;
    if (total_images < 1) {
      e.preventDefault();
      e.stopPropagation();
      document.getElementById("files_").focus();
      if (!images.parentElement.querySelector(".invalid-feedback")) {
        images.classList.add("is-invalid");
        image_feedback.classList.add("invalid-feedback");
        if (total_images < 1) {
          image_feedback.innerHTML = "Please upload at least one image";
          images.parentElement.appendChild(image_feedback);
        }
      }
    }
  });
}
[...document.getElementsByClassName("file-remove")].forEach((el) => {
  el.addEventListener("click", (e) => {
    e.preventDefault();
    e.stopPropagation();
    document.getElementById("deletefiles").value += el.id + ",";
    el.parentElement.parentElement.remove();
  });
});
[...document.getElementsByClassName("image-remove")].forEach((el) => {
  el.addEventListener("click", (e) => {
    e.preventDefault();
    e.stopPropagation();
    document.getElementById("deleteimages").value += el.id + ",";
    el.parentElement.remove();
  });
});
