import { Scorm12API, Scorm2004API } from "scorm-again";

function initScorm() {
  const iframes = document.querySelectorAll("iframe[data-learning-module-id]");
  if (!iframes.length) return;

  iframes.forEach((iframe) => {
    const learningModuleId = iframe.dataset.learningModuleId;
    let cmiData = {};

    try {
      if (iframe.dataset.cmi) {
        cmiData = JSON.parse(iframe.dataset.cmi);
      }
    } catch (e) {
      console.error("Failed to parse CMI JSON data:", e);
    }

    const settings = {
      dataCommitFormat: "flattened",
      autocommit: true,
      autocommitSeconds: 15,
      lmsCommitUrl: `/learning_area/${learningModuleId}/scorm_commit`,
      logLevel: "WARN", // Change to "DEBUG" if you need verbose LMS logs in console
    };

    // Initialize both SCORM 1.2 and 2004 so any package works
    const scorm2004 = new Scorm2004API(settings);
    const scorm12 = new Scorm12API(settings);

    if (Object.keys(cmiData).length > 0) {
      try {
        scorm2004.loadFromFlattenedJSON(cmiData);
        scorm12.loadFromFlattenedJSON(cmiData);
      } catch (err) {
        console.warn("Could not load previous CMI state:", err);
      }
    }

    // Expose both APIs to the current window
    window.API_1484_11 = scorm2004; // SCORM 2004
    window.API = scorm12; // SCORM 1.2

    // If iframe src was delayed, set it now to prevent race conditions
    if (iframe.dataset.src && !iframe.src) {
      iframe.src = iframe.dataset.src;
    }
  });
}

// Support both standard DOM loads and Turbo page transitions
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initScorm);
} else {
  initScorm();
}
document.addEventListener("turbo:load", initScorm);
