import TomSelect from "tom-select";
document.addEventListener("turbo:load", function () {
  if (document.getElementById("user_id")) {
    if (!document.getElementById("user_id").tomselect) {
      new TomSelect("#user_id", {
        placeholder: "Select a user",
        maxItems: 1,
        plugins: ["remove_button"],
      });
    }
  }
});
