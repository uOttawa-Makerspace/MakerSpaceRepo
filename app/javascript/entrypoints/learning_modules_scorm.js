import { Scorm12API, Scorm2004API } from "scorm-again";

if (!window.API_1484_11) {
  // Start up API for each scorm frame
  document.querySelectorAll("iframe[data-learning-module-id]").forEach((el) => {
    const learningModuleId = el.dataset.learningModuleId;

    const settings = {
      dataCommitFormat: "flattened",
      autocommit: true,
      autocommitSeconds: 20,
      lmsCommitUrl: `/learning_area/${learningModuleId}/scorm_commit`,
      logLevel: "INFO",
    };

    const api = new Scorm2004API(settings);
    window.API_1484_11 = api;

    api.loadFromFlattenedJSON(JSON.parse(el.dataset.cmi));
  });
}
