import { defineConfig } from "vitest/config";

// Unit tests for pure functions in app/javascript. Browser behaviour is
// covered by the Capybara system specs; this is only for logic that needs no DOM.
export default defineConfig({
  test: {
    environment: "node",
    setupFiles: ["spec/javascript/setup.js"],
    globalSetup: ["spec/javascript/global_setup.js"],
    // stubs and fake timers from one example never reach the next
    unstubGlobals: true,
    restoreMocks: true,
    include: ["spec/javascript/**/*.test.{js,ts}"],
  },
});
