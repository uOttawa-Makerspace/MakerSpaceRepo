import TomSelect from "tom-select";
document.addEventListener("turbo:load", () => {
  [...document.getElementsByClassName("pp-status-button")].forEach(
    function (element) {
      if (element.innerHTML === "Revoked") {
        element.classList.add("btn-danger");
      } else if (element.innerHTML === "Awarded") {
        element.classList.add("btn-success");
      } else {
        element.classList.add("btn-warning");
      }
    },
  );
  if (document.getElementById("training_requirements")) {
    if (!document.getElementById("training_requirements").tomselect) {
      new TomSelect("#training_requirements", {
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
      let uploaded_images =
        document.getElementsByClassName("image-item").length;
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
  if (document.getElementById("new-file-input")) {
    let cloneButton = document.getElementById("new-file-input");
    cloneButton.addEventListener("click", () => {
      let parent = cloneButton.parentElement;
      let clone = parent.cloneNode(true);
      clone.removeAttribute("id");
      clone.children[0].value = null;
      clone.children[1].className = "btn btn-danger";
      clone.children[1].children[0].className = "fa fa-trash";
      clone.children[1].addEventListener("click", (el) => {
        el.target.closest(".input-group").remove();
      });
      parent.parentElement.appendChild(clone);
    });
  }
  if (document.getElementById("new-photo-input")) {
    let cloneButton = document.getElementById("new-photo-input");
    cloneButton.addEventListener("click", () => {
      let parent = cloneButton.parentElement;
      let clone = parent.cloneNode(true);
      clone.removeAttribute("id");
      clone.children[0].value = null;
      clone.children[1].className = "btn btn-danger";
      clone.children[1].children[0].className = "fa fa-trash";
      clone.children[1].addEventListener("click", (el) => {
        el.target.closest(".input-group").remove();
      });
      parent.parentElement.appendChild(clone);
    });
  }

  const submitProjectForm = document.getElementById("submit-project-form");
  if (submitProjectForm) {
    submitProjectForm.addEventListener("submit", (event) => {
      const confirmMessage = event.target.getAttribute("data-confirm");
      if (confirmMessage && !confirm(confirmMessage)) {
        event.preventDefault();
      }
    });
  }
});
