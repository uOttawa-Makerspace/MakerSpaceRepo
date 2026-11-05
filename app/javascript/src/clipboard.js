// Buttons with class "clipboard-btn" copy either their data-clipboard-text or
// the text of the element named by data-clipboard-target.
function textToCopy(button) {
  const { clipboardText, clipboardTarget } = button.dataset;
  if (clipboardText) return clipboardText;
  const target = clipboardTarget && document.querySelector(clipboardTarget);
  if (!target) return null;
  return "value" in target ? target.value : target.textContent;
}

document.addEventListener("click", (event) => {
  const button =
    event.target instanceof Element && event.target.closest(".clipboard-btn");
  if (!button || !navigator.clipboard) return;
  const text = textToCopy(button);
  if (text !== null) navigator.clipboard.writeText(text).catch(() => {});
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
