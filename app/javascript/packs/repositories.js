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
