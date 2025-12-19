import TomSelect from "tom-select";
import "./file_upload.js";

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
        plugins: ["clear_button"],
        maxItems: 1,
      });
    }
  }
});
