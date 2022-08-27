if (document.getElementById("clone-file-input")) {
  document.getElementById("clone-file-input").addEventListener("click", () => {
    const clone = document.getElementById("new-file-input").cloneNode(true);
    clone.removeAttribute("id");
    clone.removeChild(clone.children[1]);
    clone.children[0].value = null;

    const newChild = document.createElement("button");
    newChild.className = "btn btn-danger ms-2";
    const button = document.createElement("i");
    button.className = "fa fa-trash";
    newChild.appendChild(button);
    newChild.addEventListener("click", (el) => {
      // Closest is to prevent an issue from happening depending on if they click
      // on the icon or the actual button which would make the target vary
      el.target.closest("button").parentNode.remove();
    });
    clone.appendChild(newChild);

    document.getElementById("file-input-container").append(clone);
  });
}
