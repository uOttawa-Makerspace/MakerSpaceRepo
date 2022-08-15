if (document.getElementById("project_proposal_categories")) {
  if (!document.getElementById("project_proposal_categories").tomselect) {
    new TomSelect("#project_proposal_categories", {
      plugins: ["remove_button"],
      maxItems: 5,
    });
  }
}
if (document.getElementById("link-list")) {
  document
    .getElementById("link-list")
    .addEventListener("click", function (event) {
      let listItem = document.createElement("li");
      let listDiv = document.createElement("div");
      let listInput = document.createElement("input");
      listDiv.classList.add("mb-3");
      listInput.classList.add("form-control");
      listInput.setAttribute("type", "text");
      listInput.placeholder = "Ajoutez un lien / Add a link";
      listDiv.appendChild(listInput);
      listItem.appendChild(listDiv);
      document.getElementsByClassName("main_ul")[0].appendChild(listItem);
    });
}
if (document.getElementById("link-list")) {
  document
    .getElementById("link-list")
    .addEventListener("click", function (event) {
      let listItem = document.createElement("li");
      let listDiv = document.createElement("div");
      let listInput = document.createElement("input");
      listDiv.classList.add("mb-3");
      listInput.classList.add("form-control");
      listInput.setAttribute("type", "text");
      listInput.placeholder = "Ajoutez un lien / Add a link";
      listDiv.appendChild(listInput);
      listItem.appendChild(listDiv);
      document.getElementsByClassName("main_ul")[0].appendChild(listItem);
    });
}
if (document.getElementById("remove-link-list")) {
  document
    .getElementById("remove-link-list")
    .addEventListener("click", function (event) {
      let listItem = document.getElementsByClassName("main_ul")[0].lastChild;
      document.getElementsByClassName("main_ul")[0].removeChild(listItem);
    });
}

if (document.getElementById("waiting-save-button")) {
  document
    .getElementById("waiting-save-button")
    .addEventListener("click", function (event) {
      let past_exp = document.getElementById(
        "project_proposal_past_experiences"
      );
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
    });
}
let form =
  document.getElementById("new_project_proposal") ||
  document.getElementsByClassName("edit_project_proposal")[0];
if (form) {
  form.addEventListener("submit", (e) => {
    let clientBackground = document.querySelector(
      "trix-editor[input='project_proposal_client_background']"
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
      "trix-editor[input='project_proposal_description']"
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
          projectDescriptionFeedback
        );
      }
    }
  });
}
