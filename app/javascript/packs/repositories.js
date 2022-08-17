window.showPass = function () {
  document.getElementById("password_repo_field").style.display = "block";
};

window.hidePass = function () {
  if (document.getElementById("change_pass"))
    document.getElementById("change_pass").style.display = "none";
  if (document.getElementById("password_repo_field"))
    document.getElementById("password_repo_field").style.display = "none";
};
window.togglePass = function () {
  var x = document.getElementById("password_repo_field");
  if (x.style.display === "none") {
    x.style.display = "block";
  } else {
    x.style.display = "none";
  }
};

if (document.getElementById("search_users_add")) {
  if (!document.getElementById("search_users_add").tomselect) {
    new TomSelect("#search_users_add", {
      searchField: ["name"],
      valueField: "id",
      labelField: "name",
      maxOptions: 5,
      searchPlaceholder: "Add Owner...",
      searchOnKeyUp: true,
      load: function (type, callback) {
        if (type.length < 2) {
          return;
        } else {
          let url = "/repositories/populate_users?search=" + type;
          fetch(url)
            .then((response) => response.json())
            .then((data) => {
              callback(
                data.users.map((user) => {
                  return { id: user.id, name: user.name };
                })
              );
            });
        }
      },
      shouldLoad: function (type) {
        return type.length > 2;
      },
    });
  }
}
if (document.getElementById("search_users_remove")) {
  if (!document.getElementById("search_users_remove").tomselect) {
    new TomSelect("#search_users_remove", {
      searchField: ["name"],
      valueField: "id",
      labelField: "name",
      maxOptions: null,
      searchOnKeyUp: true,
    });
  }
}
if (document.getElementById("search_project_proposals")) {
  if (!document.getElementById("search_project_proposals").tomselect) {
    new TomSelect("#search_project_proposals", {
      searchField: ["name"],
      valueField: "id",
      labelField: "name",
      maxOptions: null,
      searchOnKeyUp: true,
    });
  }
}
if (document.getElementById("repository_categories")) {
  if (!document.getElementById("repository_categories").tomselect) {
    new TomSelect("#repository_categories", {
      plugins: ["remove_button"],
      maxItems: 5,
    });
  }
}
if (document.getElementById("repository_equipments")) {
  if (!document.getElementById("repository_equipments").tomselect) {
    new TomSelect("#repository_equipments", {
      plugins: ["remove_button"],
      maxItems: 5,
    });
  }
}
if (document.getElementById("repository_project_proposal_id")) {
  if (!document.getElementById("repository_project_proposal_id").tomselect) {
    new TomSelect("#repository_project_proposal_id", {
      plugins: ["remove_button"],
      maxItems: 1,
    });
  }
}
let form =
  document.getElementById("new_repository") ||
  document.getElementsByClassName("edit_repository")[0];
if (form) {
  form.addEventListener("submit", (e) => {
    let images = document.getElementById("images_");
    let image_feedback = document.createElement("div");
    let uploaded_images = document.getElementsByClassName("image-item").length;
    let total_images = uploaded_images + images.files.length;
    if (total_images < 1 || total_images > 5) {
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
document.querySelectorAll(".invalid-feedback").forEach((el) => {
  if (el.innerHTML == "") {
    el.style.display = "none";
  }
});
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
