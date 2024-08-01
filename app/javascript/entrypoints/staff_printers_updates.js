window.populateMessageModal = function (element) {
  //console.log(element.dataset.username + ' / ' + element.dataset.printerNumber)
  let user_select = document.getElementById("user_dashboard_select").tomselect;
  user_select.clearOptions(); // Clear prev options
  user_select.addOption({
    id: element.dataset.username,
    name: element.dataset.username,
  }); // Add our username manually
  user_select.setValue(element.dataset.username); // Set that username
  document.getElementById("printerNumberSelect").value =
    element.dataset.printerNumber; // printers are already loaded - this isn't a tomselect i think
  document.getElementById("print_failed_message_staff_notes").value = "";
};
document.querySelectorAll(".print-failed-button").forEach((e) => {
  e.addEventListener("click", (event) => populateMessageModal(event.target));
});
