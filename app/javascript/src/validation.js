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
  const newPhotosCount =
    typeof photoFiles !== "undefined" && Array.isArray(photoFiles)
      ? photoFiles.length
      : 0;
  const repoImageContainer = document.querySelector("div.repo-image");

  if (newPhotosCount === 0 && oldPhotosCount === 0 && repoImageContainer) {
    repoImageContainer.before(
      createErrorSpan("At least one photo is required."),
    );
    isValid = false;
  }

  return isValid;
}

export function validation_proposal() {
  const name = document.querySelector("input#project_proposal_username");
  const email = document.querySelector("input#project_proposal_email");
  const client = document.querySelector("input#project_proposal_client");
  const title = document.querySelector("input#project_proposal_title");
  const clientBackground = document.querySelector(
    "input#client_background_trix_input_project_proposal",
  );
  const description = document.querySelector("#trix_editor");

  document
    .querySelectorAll("span.form-error.repo-form")
    .forEach((el) => el.remove());
  const regex = /^[-a-zA-Z\d\s]*$/;

  if (name && name.value.trim().length === 0) {
    name.before(createErrorSpan("Your name is required"));
    scrollToError("project_proposal_username");
    return false;
  }

  if (email && email.value.trim().length === 0) {
    email.before(createErrorSpan("Your email is required"));
    scrollToError("project_proposal_email");
    return false;
  }

  if (client && client.value.trim().length === 0) {
    client.before(createErrorSpan("Client is required"));
    scrollToError("project_proposal_client");
    return false;
  }

  if (title) {
    const titleVal = title.value.trim();
    if (titleVal.length === 0) {
      title.before(createErrorSpan("Project title is required."));
      scrollToError("project_proposal_title");
      return false;
    }

    if (!regex.test(titleVal)) {
      title.before(
        createErrorSpan("Project title may only contain letters and numbers."),
      );
      scrollToError("project_proposal_title");
      return false;
    }
  }

  if (clientBackground && clientBackground.value.trim().length === 0) {
    clientBackground.before(createErrorSpan("Client background is required."));
    scrollToError("project_proposal_client_background");
    return false;
  }

  if (description && description.textContent.trim().length === 0) {
    description.before(createErrorSpan("Description is required."));
    scrollToError("trix_editor");
    return false;
  }

  return true;
}

// Preserve legacy naming for inline HTML onsubmit handlers
window.validation = validation;
window.validation_proposal = validation_proposal;
window.scrow_to_error = scrollToError;
window.scrollToError = scrollToError;
