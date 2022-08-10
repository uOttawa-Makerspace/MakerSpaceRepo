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
