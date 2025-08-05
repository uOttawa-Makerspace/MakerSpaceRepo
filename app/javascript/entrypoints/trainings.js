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

// Pass single element
const element = document.getElementById("#skills-input");
const choices = new Choices(element, {
  choices: [
    {
      value: "Option 1",
      label: "Option 1",
      selected: true,
      disabled: false,
    },
    {
      value: "Option 2",
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
          value: "Option 3",
          label: "Option 4",
          selected: true,
          disabled: false,
        },
        {
          value: "Option 2",
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
});
