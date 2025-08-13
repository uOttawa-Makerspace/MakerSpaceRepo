import "tom-select";
import TomSelect from "tom-select";

document.addEventListener("turbo:load", () => {
  [...document.getElementsByClassName("sk-delete-button")].forEach((btn) =>
    btn.addEventListener("click", (el) => {
      el.target.closest("button").parentNode.remove();
    }),
  );

  document.getElementById("new-sk").addEventListener("click", () => {
    const clone = document.getElementById("new-link-input").cloneNode(true);
    document.getElementById("link-container").append(clone);
    clone.removeAttribute("id");
    clone.querySelectorAll("input").forEach((input) => {
      input.value = "";
    });
    clone.querySelector("button").addEventListener("click", (el) => {
      el.target.closest("button").parentNode.remove();
    });
    clone.style.visibility = "visible";
  });
});

document.addEventListener("turbo:load", () => {
  new TomSelect("#select-skills", {
    sortField: "text",
  });
});

const test = document.querySelector("#skill_select");
test.addEventListener("click", () => {
  console.log("Selected");
  new TomSelect("#skill_select", {
    sortField: "text",
  });
});

if (document.getElementById("#search_bar")) {
  document
    .getElementById("search_bar")
    .addEventListener("keyup", function (event) {
      event.preventDefault();
      let query = document.getElementById("search_bar").value;
      if (query == "") {
        query = ".";
      }
      if (query.length > 2 || query == ".") {
        let url =
          "/admin/trainings/" +
          window.location.search("id") +
          "/edit?search=" +
          query;
        fetch(url, {
          method: "GET",
          headers: {
            Accept: "*/*",
          },
        })
          .then((response) => response.text())
          .then((data) => {
            document.getElementsByClassName("skills_list")[0].innerHTML = data;
          });
      }
    });
}
