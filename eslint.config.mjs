import js from "@eslint/js";
import globals from "globals";

// Names that are defined outside the module that uses them: set on window by
// another script, provided by a library's own script tag, or defined by an
// inline script in a view.
const pageGlobals = {
  debounce: "readonly",
  Turbo: "readonly",
  Chartkick: "readonly",
  YT: "readonly",
  issueSummary: "readonly",
  populateMessageModal: "readonly",
  check_proficient_project: "readonly",
  check_learning_module: "readonly",
  // the flatpickr module sets window.flatpickr when it is imported
  flatpickr: "readonly",
};

export default [
  {
    // .worktrees and doc hold local-only checkouts and tooling (with their own node_modules)
    ignores: [
      "public/**",
      "node_modules/**",
      "tmp/**",
      "coverage/**",
      ".worktrees/**",
      "doc/**",
      "vendor/**",
    ],
  },
  {
    files: ["app/javascript/**/*.js"],
    ...js.configs.recommended,
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      globals: { ...globals.browser, ...pageGlobals },
    },
    rules: {
      ...js.configs.recommended.rules,
      complexity: ["error", 7],
      "max-depth": ["error", 4],
    },
  },
  {
    files: ["spec/javascript/**/*.js"],
    ...js.configs.recommended,
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      globals: { ...globals.browser, ...globals.node, ...pageGlobals },
    },
    rules: { ...js.configs.recommended.rules },
  },
];
