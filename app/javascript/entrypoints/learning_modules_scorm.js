import { Scorm12API, Scorm2004API } from "scorm-again";

if (!window.API) {
  // Start up API for each scorm frame
  document.querySelectorAll("iframe[data-learning-module-id]").forEach((el) => {
    const learningModuleId = el.dataset.learningModuleId;

    const settings = {
      autocommit: true,
      autocommitSeconds: 60,
      lmsCommitUrl: `/learning_module/${learningModuleId}/scorm_commit`,
      logLevel: "INFO",
    };

    const api = new Scorm2004API(settings);

    window.API_1484_11 = api;
  });
}
