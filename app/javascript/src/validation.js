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

const PROPOSAL_TITLE_CHARS = /^[-a-zA-Z\d\s]*$/;

function isBlank(text) {
  return text.trim().length === 0;
}

function requiredValue(message) {
  return (field) => (isBlank(field.value) ? message : null);
}

function proposalTitleProblem(title) {
  const titleVal = title.value.trim();
  if (titleVal.length === 0) return "Project title is required.";
  if (!PROPOSAL_TITLE_CHARS.test(titleVal)) {
    return "Project title may only contain letters and numbers.";
  }
  return null;
}

// The proposal form's checks, in order. A field that is not on the page is
// not checked.
const PROPOSAL_CHECKS = [
  {
    selector: "input#project_proposal_username",
    scrollId: "project_proposal_username",
    problemOf: requiredValue("Your name is required"),
  },
  {
    selector: "input#project_proposal_email",
    scrollId: "project_proposal_email",
    problemOf: requiredValue("Your email is required"),
  },
  {
    selector: "input#project_proposal_client",
    scrollId: "project_proposal_client",
    problemOf: requiredValue("Client is required"),
  },
  {
    selector: "input#project_proposal_title",
    scrollId: "project_proposal_title",
    problemOf: proposalTitleProblem,
  },
  {
    selector: "input#client_background_trix_input_project_proposal",
    scrollId: "project_proposal_client_background",
    problemOf: requiredValue("Client background is required."),
  },
  {
    selector: "#trix_editor",
    scrollId: "trix_editor",
    problemOf: (field) =>
      isBlank(field.textContent) ? "Description is required." : null,
  },
];

// Shows the first problem only, before its field, and scrolls to it.
export function validation_proposal() {
  const checks = PROPOSAL_CHECKS.map((check) => ({
    ...check,
    field: document.querySelector(check.selector),
  }));

  document
    .querySelectorAll("span.form-error.repo-form")
    .forEach((el) => el.remove());

  for (const { field, scrollId, problemOf } of checks) {
    const message = field && problemOf(field);
    if (message) {
      field.before(createErrorSpan(message));
      scrollToError(scrollId);
      return false;
    }
  }

  return true;
}

// Preserve legacy naming for inline HTML onsubmit handlers
window.validation = validation;
window.validation_proposal = validation_proposal;
window.scrow_to_error = scrollToError;
window.scrollToError = scrollToError;
