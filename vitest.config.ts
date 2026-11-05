import { defineConfig } from "vitest/config";

// Unit tests for pure functions in app/javascript. Browser behaviour is
// covered by the Capybara system specs; this is only for logic that needs no DOM.
export default defineConfig({
  test: {
    environment: "node",
    include: ["spec/javascript/**/*.test.{js,ts}"],
  },
});
