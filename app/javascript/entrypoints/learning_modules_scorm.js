document.addEventListener("turbo:load", function () {
  const scormContainer = document.querySelector("iframe#scorm-container");
  if (!scormContainer) {
    console.error("Did not find a scorm container. Exiting");
    return;
  }

  const learningModuleId = scormContainer.dataset.learningModuleId;

  // These are defaults
  const cmiData = {
    // SCORM 1.2 state data
    "cmi.core.lesson_status": "not attempted",
    "cmi.core.lesson_location": "",
    "cmi.core.score.raw": "",
    "cmi.core.score.min": "0",
    "cmi.core.score.max": "100",
    "cmi.core.session_time": "00:00:00",
    "cmi.core.total_time": "00:00:00",
    "cmi.suspend_data": "",
    "cmi.core.entry": "ab-initio",
    "cmi.core.exit": "",
    "cmi.core.credit": "credit",
    "cmi.core.lesson_mode": "normal",

    // SCORM 2004 state data
    "cmi.completion_status": "not attempted",
    "cmi.success_status": "unknown",
    "cmi.location": "",
    "cmi.score.raw": "",
    "cmi.score.min": "0",
    "cmi.score.max": "100",
    "cmi.score.scaled": "",
    "cmi.session_time": "PT0H0M0S",
    "cmi.total_time": "PT0H0M0S",
    "cmi.entry": "ab-initio",
    "cmi.exit": "",
    "cmi.credit": "credit",
    "cmi.mode": "normal",
    "cmi.progress_measure": "",
  };

  let lastError = "0";
  let initialized = false;

  /* SCORM 1.2 */
  window.API = {
    LMSInitialize: function () {
      initialized = true;
      lastError = "0";
      return "true";
    },

    LMSFinish: function () {
      // TODO: Save cmiData to your backend
      initialized = false;
      return "true";
    },

    LMSGetValue: function (key) {
      if (!initialized) {
        lastError = "301";
        return "";
      }
      lastError = "0";
      return cmiData[key] !== undefined ? cmiData[key] : "";
    },

    LMSSetValue: function (key, value) {
      if (!initialized) {
        lastError = "301";
        return "false";
      }
      cmiData[key] = value;
      lastError = "0";

      if (
        key === "cmi.core.lesson_status" &&
        (value === "completed" || value === "passed")
      ) {
        // TODO: Handle completion
      }

      return "true";
    },

    LMSCommit: function () {
      // TODO: Persist cmiData if needed
      return "true";
    },

    LMSGetLastError: function () {
      return lastError;
    },
    LMSGetErrorString: function (code) {
      return (
        {
          0: "No Error",
          101: "General Exception",
          301: "Not Initialized",
        }[code] || "Unknown Error"
      );
    },
    LMSGetDiagnostic: function (code) {
      return this.LMSGetErrorString(code);
    },
  };

  /* SCORM 2004 */
  window.API_1484_11 = {
    Initialize: function () {
      initialized = true;
      lastError = "0";
      return "true";
    },

    Terminate: function () {
      // TODO: Save cmiData to your backend
      initialized = false;
      return "true";
    },

    GetValue: function (key) {
      if (!initialized) {
        lastError = "122";
        return "";
      }
      lastError = "0";
      return cmiData[key] !== undefined ? cmiData[key] : "";
    },

    SetValue: function (key, value) {
      if (!initialized) {
        lastError = "122";
        return "false";
      }
      cmiData[key] = value;
      lastError = "0";

      if (key === "cmi.completion_status" && value === "completed") {
        // TODO: Handle completion
      }

      return "true";
    },

    Commit: function () {
      // TODO: Persist cmiData if needed
      return "true";
    },

    GetLastError: function () {
      return lastError;
    },
    GetErrorString: function (code) {
      return (
        {
          0: "No Error",
          101: "General Exception",
          122: "Not Initialized",
        }[code] || "Unknown Error"
      );
    },
    GetDiagnostic: function (code) {
      return this.GetErrorString(code);
    },
  };
});
