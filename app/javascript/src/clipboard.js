// Why is this a full-blown import
import Clipboard from "clipboard";
document.addEventListener("DOMContentLoaded", function () {
  var clipboard = new Clipboard(".clipboard-btn");
});

window.copyField = function (id, btn) {
  navigator.clipboard
    .writeText(document.querySelector(id).textContent)
    .then(() => {
      let prevText = btn.textContent;
      btn.textContent = "Copied!";
      setTimeout(() => (btn.textContent = prevText), 2000);
    })
    .catch(() => (btn.textContent = "Failed"));
};
