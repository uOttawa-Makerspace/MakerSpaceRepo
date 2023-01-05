import TomSelect from "tom-select";
console.log("staff_training_sessions.js");
document.addEventListener("turbolinks:load", function () {
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
