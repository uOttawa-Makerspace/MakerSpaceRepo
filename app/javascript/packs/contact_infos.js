document.addEventListener("turbolinks:load", function () {
  if (document.getElementById("contact_info_space_id")) {
    console.log("contact_info_space_id found");
    if (!document.getElementById("contact_info_space_id").tomselect) {
      new TomSelect("#contact_info_space_id", {
        plugins: ["remove_button", "restore_on_backspace", "clear_button"],
        create: true,
        persist: false,
      });
    }
  }
});
