import { oncePerElement, onEveryPageLoad } from "../src/on_page.js";
import { tomSelectFor } from "../src/tom_select.js";
import "../src/file_upload.js";

const bindAddLink = oncePerElement((button) =>
  button.addEventListener("click", function (event) {
    let listItem = document.createElement("li");
    let listDiv = document.createElement("div");
    let listInput = document.createElement("input");
    listDiv.classList.add("mb-3");
    listInput.classList.add("form-control");
    listInput.setAttribute("type", "text");
    listInput.placeholder = "https://...";
    listDiv.appendChild(listInput);
    listItem.appendChild(listDiv);
    document.getElementsByClassName("main_ul")[0].appendChild(listItem);
  }),
);

const bindRemoveLink = oncePerElement((button) =>
  button.addEventListener("click", function (event) {
    let listItem = document.getElementsByClassName("main_ul")[0].lastChild;
    document.getElementsByClassName("main_ul")[0].removeChild(listItem);
  }),
);

const bindSaveForLater = oncePerElement((button) =>
  button.addEventListener("click", function (event) {
    let past_exp = document.getElementById("project_proposal_past_experiences");
    let past_exp_add = past_exp.value + "|";
    while (document.getElementsByClassName("main_ul")[0].lastChild) {
      past_exp_add +=
        document.getElementsByClassName("main_ul")[0].lastChild.lastChild
          .lastChild.value + ",";
      document
        .getElementsByClassName("main_ul")[0]
        .removeChild(document.getElementsByClassName("main_ul")[0].lastChild);
    }
    past_exp.value = past_exp_add;
  }),
);

const bindSubmitChecks = oncePerElement((form) =>
  form.addEventListener("submit", (e) => {
    let clientBackground = document.querySelector(
      "trix-editor[input='project_proposal_client_background']",
    );
    let clientBackgroundValue = clientBackground.value;
    if (clientBackgroundValue.length < 1) {
      e.preventDefault();
      e.stopPropagation();
      clientBackground.focus();
      clientBackground.style.border = "1px solid #dc3545";
      if (!clientBackground.parentElement.querySelector(".invalid-feedback")) {
        let clientFeedback = document.createElement("div");
        clientFeedback.classList.add("invalid-feedback");

        clientFeedback.innerText =
          "Veuillez entrer le contexte du client / Please enter client's background";
        clientBackground.parentElement.appendChild(clientFeedback);
        clientBackground.classList.add("is-invalid");
      }
    }
    let projectDescription = document.querySelector(
      "trix-editor[input='project_proposal_description']",
    );
    let projectDescriptionValue = projectDescription.value;
    if (projectDescriptionValue.length < 1) {
      e.preventDefault();
      e.stopPropagation();
      projectDescription.focus();
      projectDescription.style.border = "1px solid #dc3545";
      if (
        !projectDescription.parentElement.querySelector(".invalid-feedback")
      ) {
        let projectDescriptionFeedback = document.createElement("div");
        projectDescriptionFeedback.classList.add("invalid-feedback");
        projectDescriptionFeedback.innerText =
          "Veuillez entrer une description de votre projet / Please enter a description of your project";
        projectDescription.classList.add("is-invalid");
        projectDescription.parentElement.appendChild(
          projectDescriptionFeedback,
        );
      }
    }
  }),
);

// The add buttons of the file and photo inputs: each adds another input row
// with a button that removes it.
const bindAddInputRow = oncePerElement((cloneButton) =>
  cloneButton.addEventListener("click", () => {
    let parent = cloneButton.parentElement;
    let clone = parent.cloneNode(true);
    clone.removeAttribute("id");
    clone.children[0].value = null;
    clone.children[1].className = "btn btn-danger";
    clone.children[1].children[0].className = "fa fa-trash";
    parent.parentElement.appendChild(clone);
  }),
);

// The remove buttons of the added input rows, listened to on the rows' parent,
// so the rows of a page Turbo restores from its cache can be removed too.
const bindRemoveInputRow = oncePerElement((rows) =>
  rows.addEventListener("click", (event) => {
    const remove = event.target.closest(".input-group > .btn-danger");
    if (remove && rows.contains(remove)) remove.parentElement.remove();
  }),
);

function bindInputRows(addButton) {
  bindAddInputRow(addButton);
  bindRemoveInputRow(addButton?.parentElement.parentElement);
}

// The links saved with the proposal, shown as link fields. A page Turbo
// restores from its cache already shows them, so they are added only to an
// empty list.
const showSavedLinks = oncePerElement((savedLinks) => {
  const list = document.getElementsByClassName("main_ul")[0];
  if (list.children.length > 0) return;
  let urls = savedLinks.value.split(/[\|,]/);
  console.log(urls);
  if (urls[0] != "") {
    for (let i = 1; i < urls.length; i++) {
      if (urls[i] == "") continue;
      //urls[i] = urls[i].split(",")[1];
      let listItem = document.createElement("li");
      let listDiv = document.createElement("div");
      let listInput = document.createElement("input");
      listDiv.classList.add("mb-3");
      listInput.classList.add("form-control");
      listInput.setAttribute("type", "text");
      listInput.placeholder = "Ajoutez un lien / Add a link";
      listInput.value = urls[i];
      listDiv.appendChild(listInput);
      listItem.appendChild(listDiv);
      list.appendChild(listItem);
    }
  }
});

function proposalForm() {
  return (
    document.getElementById("new_project_proposal") ||
    document.getElementsByClassName("edit_project_proposal")[0]
  );
}

onEveryPageLoad(() => {
  const categories = document.getElementById("project_proposal_categories");
  if (categories) {
    tomSelectFor(categories, { plugins: ["remove_button"], maxItems: 5 });
  }
  bindAddLink(document.getElementById("link-list"));
  bindRemoveLink(document.getElementById("remove-link-list"));
  bindSaveForLater(document.getElementById("waiting-save-button"));
  bindSubmitChecks(proposalForm());
  bindInputRows(document.getElementById("new-file-input"));
  bindInputRows(document.getElementById("new-photo-input"));
  showSavedLinks(document.getElementById("ignore_past_experiences"));
});
