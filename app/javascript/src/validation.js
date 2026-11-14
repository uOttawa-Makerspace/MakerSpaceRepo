function createErrorSpan(message) {
  const span = document.createElement("span");
  span.className = "form-error repo-form";
  span.textContent = message;
  return span;
}

export function scrollToError(elementId) {
  const el = document.getElementById(elementId);
  if (!el) return;

  const yOffset = -170;
  const y = el.getBoundingClientRect().top + window.pageYOffset + yOffset;
  window.scrollTo({ top: y, behavior: "smooth" });
}

export function validation() {
  let isValid = true;
  const titleInput = document.getElementById("repository_title");

  // Clear previous error messages
  document
    .querySelectorAll("span.form-error.repo-form")
    .forEach((el) => el.remove());

  const regex = /^[-a-zA-Z\d\s]*$/;

  if (titleInput) {
    const titleVal = titleInput.value.trim();
    if (titleVal.length === 0) {
      titleInput.before(createErrorSpan("Project title is required."));
      isValid = false;
    } else if (!regex.test(titleVal)) {
      titleInput.before(
        createErrorSpan("Project title may only contain letters and numbers."),
      );
      isValid = false;
    }
  }

  const oldPhotosCount = document.querySelectorAll(
    "#image-container > div",
  ).length;
  const repoImageContainer = document.querySelector("div.repo-image");

  if (oldPhotosCount === 0 && repoImageContainer) {
    repoImageContainer.before(
      createErrorSpan("At least one photo is required."),
    );
    isValid = false;
  }

  return isValid;
}

// Preserve legacy naming for inline HTML onsubmit handlers
window.validation = validation;
window.scrow_to_error = scrollToError;
window.scrollToError = scrollToError;
