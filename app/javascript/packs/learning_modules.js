import Sortable from "sortablejs";

const sortables = [];

document.addEventListener("turbolinks:load", () => {
  const reorderElements = [...document.getElementsByClassName("reorder")];
  reorderElements.forEach((reorderElement) => {
    reorderElement.addEventListener("click", (e) => {
      let sortable = sortables.find(
        (el) => el.name === e.target.dataset.accordion
      );
      if (!sortable || !sortable.value) {
        sortable = Sortable.create(
          document.getElementById(e.target.dataset.accordion),
          {
            disabled: !e.target.checked,
            onEnd: (e) => {
              fetch("/learning_area/reorder", {
                method: "PUT",
                headers: {
                  Accept: "application/json",
                  "Content-Type": "application/json",
                },
                body: JSON.stringify({
                  data: [...e.from.children].map((c) => c.dataset.id),
                  format: "json",
                }),
              }).catch((error) => {
                console.log("An error occurred: " + error.message);
              });
            },
          }
        );
        sortables.push({
          name: e.target.dataset.accordion,
          value: sortable,
        });
      } else {
        sortable.value.option("disabled", !e.target.checked);
      }
    });
  });
});
let form =
  document.getElementById("new_learning_module") ||
  document.getElementsByClassName("edit_repository")[0];
if (form) {
  form.addEventListener("submit", (e) => {
    let images = document.getElementById("images_");
    let image_feedback = document.createElement("div");
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
          image_feedback.innerHTML = "You must upload at least one image";
        } else if (total_images > 5) {
          image_feedback.innerHTML = "You can upload a maximum of 5 images";
        }
        images.parentNode.appendChild(image_feedback);
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
