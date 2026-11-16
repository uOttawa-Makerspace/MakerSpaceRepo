import { pageText, showFailure } from "./request_error";

// Buttons with class "clipboard-btn" copy either their data-clipboard-text or
// the text of the element named by data-clipboard-target.
function textToCopy(button) {
  const { clipboardText, clipboardTarget } = button.dataset;
  if (clipboardText) return clipboardText;
  const target = clipboardTarget && document.querySelector(clipboardTarget);
  if (!target) return null;
  return "value" in target ? target.value : target.textContent;
}

// The browser refused the copy (no permission, insecure page): say so rather than leave the user guessing.
function copyFailed() {
  showFailure(pageText("requestCopyFailed"));
}

document.addEventListener("click", (event) => {
  const button =
    event.target instanceof Element && event.target.closest(".clipboard-btn");
  if (!button) return;
  if (!navigator.clipboard) return copyFailed();
  const text = textToCopy(button);
  if (text !== null) navigator.clipboard.writeText(text).catch(copyFailed);
});

window.copyField = function (id, btn) {
  navigator.clipboard
    .writeText(document.querySelector(id).textContent)
    .then(() => {
      let prevText = btn.textContent;
      btn.textContent = "Copied!";
      setTimeout(() => (btn.textContent = prevText), 2000);
    })
    .catch(copyFailed);
};
