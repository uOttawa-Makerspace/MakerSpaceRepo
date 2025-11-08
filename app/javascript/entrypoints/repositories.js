import TomSelect from "tom-select";
window.showPass = function () {
  document.getElementById("pass").style.display = "block";
};

window.hidePass = function () {
  if (document.getElementById("change_pass"))
    document.getElementById("change_pass").style.display = "none";
  if (document.getElementById("pass"))
    document.getElementById("pass").style.display = "none";
};
window.togglePass = function () {
  // dont think this is used
  var x = document.getElementById("password_repo_field");
  if (x.style.display === "none") {
    x.style.display = "block";
  } else {
    x.style.display = "none";
  }
};
document.addEventListener("turbo:load", () => {
  if (document.getElementById("owner_select")) {
    if (!document.getElementById("owner_select").tomselect) {
      new TomSelect("#owner_select", {
        searchField: ["username"],
        valueField: "id",
        labelField: "username",
        maxOptions: 5,
        searchPlaceholder: "Add Owner...",
        searchOnKeyUp: true,
        openOnFocus: false,
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
                    return { id: user.id, username: user.username };
                  }),
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

  if (document.getElementById("search_users_add")) {
    if (!document.getElementById("search_users_add").tomselect) {
      new TomSelect("#search_users_add", {
        searchField: ["username"],
        valueField: "id",
        labelField: "username",
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
                    return { id: user.id, username: user.username };
                  }),
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
        searchField: ["username"],
        valueField: "id",
        labelField: "username",
        maxOptions: null,
        searchOnKeyUp: true,
      });
    }
  }
  if (document.getElementById("search_users_transfer")) {
    if (!document.getElementById("search_users_transfer").tomselect) {
      new TomSelect("#search_users_transfer", {
        searchField: ["username"],
        valueField: "id",
        labelField: "username",
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
        openOnFocus: false,
      });
    }
  }
  if (document.getElementById("repository_categories")) {
    if (!document.getElementById("repository_categories").tomselect) {
      new TomSelect("#repository_categories", {
        plugins: ["remove_button"],
        maxItems: 5,
        openOnFocus: true,
      });
    }
  }
  if (document.getElementById("repository_equipments")) {
    if (!document.getElementById("repository_equipments").tomselect) {
      new TomSelect("#repository_equipments", {
        plugins: ["remove_button"],
        maxItems: 5,
        openOnFocus: true,
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
});
let form =
  document.getElementById("new_repository") ||
  document.getElementsByClassName("edit_repository")[0] ||
  document.getElementById("makes_new");
if (form) {
  form.addEventListener("submit", (e) => {
    let images = document.getElementById("images_");
    let aux_image_length = [...document.getElementsByClassName("image-upload")];
    let image_feedback = document.createElement("div");
    image_feedback.classList.add("text-center");
    let uploaded_images = document.getElementsByClassName("image-item").length;
    let total_images = [
      ...document.getElementsByClassName("image-upload"),
    ].reduce((acc, curr) => {
      acc += curr.files.length;
      return acc;
    }, uploaded_images + images.files.length);
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
