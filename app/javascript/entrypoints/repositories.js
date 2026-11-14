import TomSelect from "tom-select";
import "../src/file_upload.js";

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

// Asks the server for the users matching the typed text, from two
// characters on (TomSelect itself only calls this past two, see shouldLoad).
function loadUsers(type, callback) {
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
}

function shouldLoadUsers(type) {
  return type.length > 2;
}

function userSelectOptions(maxOptions, extra) {
  return {
    searchField: ["username"],
    valueField: "id",
    labelField: "username",
    maxOptions: maxOptions,
    ...extra,
  };
}

function userSearchOptions(extra) {
  return userSelectOptions(5, {
    searchPlaceholder: "Add Owner...",
    searchOnKeyUp: true,
    ...extra,
    load: loadUsers,
    shouldLoad: shouldLoadUsers,
  });
}

function projectProposalOptions() {
  return {
    render: {
      option: function (data, escape) {
        return `<div>
            <span>${escape(data.text)}</span>
            <br />
            <small class="text-muted">${escape(data.semester || "")}</small>
            </div>`;
      },
      item: function (data, escape) {
        return `<span>
            ${escape(data.text)}
            <br />
            <small class="text-muted">${escape(data.semester || "")}</small>
            </span>`;
      },
    },
  };
}

// The selects of the repository pages, in the order they are decorated, each
// with a fresh options object for this page load.
function repositorySelects() {
  return [
    ["owner_select", userSearchOptions({ openOnFocus: false })],
    ["search_users_add", userSearchOptions({})],
    ["search_users_remove", userSelectOptions(null, { searchOnKeyUp: true })],
    ["search_users_transfer", userSelectOptions(null, { searchOnKeyUp: true })],
    ["search_project_proposals", projectProposalOptions()],
    [
      "repository_categories",
      { plugins: ["remove_button"], maxItems: 5, openOnFocus: true },
    ],
    [
      "repository_equipments",
      {
        plugins: ["remove_button"],
        maxItems: 5,
        openOnFocus: true,
        create: true,
      },
    ],
    [
      "repository_project_proposal_id",
      { plugins: ["clear_button"], maxItems: 1 },
    ],
  ];
}

// Decorates the select with this id once: a select that already has its
// TomSelect (an earlier load of the same page) is left alone.
function decorateSelect(id, options) {
  const select = document.getElementById(id);
  if (select && !select.tomselect) {
    new TomSelect("#" + id, options);
  }
}

document.addEventListener("turbo:load", () => {
  repositorySelects().forEach(([id, options]) => decorateSelect(id, options));
});
