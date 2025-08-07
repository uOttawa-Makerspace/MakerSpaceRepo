import "choices.js/public/assets/styles/choices.css";

document.addEventListener("DOMContentLoaded", () => {
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

if (document.getElementById("search_bar")) {
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

// Pass single element
const element = document.getElementById("#skills-input");
const choices = new Choices(element, {
  choices: [
    {
      value: "A 1",
      label: "Option 1",
      selected: true,
      disabled: false,
    },
    {
      value: "A 2",
      label: "Option 2",
      selected: false,
      disabled: true,
      customProperties: {
        description: "Custom description about Option 2",
        random: "Another random custom property",
      },
    },
    {
      label: "Group 1",
      choices: [
        {
          value: "A 3",
          label: "Option 4",
          selected: true,
          disabled: false,
        },
        {
          value: "B 2",
          label: "Option 2",
          selected: false,
          disabled: true,
          customProperties: {
            description: "Custom description about Option 2",
            random: "Another random custom property",
          },
        },
      ],
    },
  ],
  searchChoices: true,
});
