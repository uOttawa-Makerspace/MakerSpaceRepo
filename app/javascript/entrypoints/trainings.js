import TomSelect from "tom-select";

document.addEventListener("turbo:load", () => {
  if (document.querySelector("#training_list_of_skills_en")) {
    new TomSelect("#training_list_of_skills_en", {
      sortField: "text",
      create: true,
      plugins: {
        remove_button: {
          title: "Remove skill",
        },
      },
      persist: false,
    });
  }
});

document.addEventListener("turbo:load", () => {
  if (document.querySelector("#training_list_of_skills_fr")) {
    new TomSelect("#training_list_of_skills_fr", {
      sortField: "text",
      create: true,
      plugins: {
        remove_button: {
          title: "Remove skill",
        },
      },
      persist: false,
    });
  }
});
