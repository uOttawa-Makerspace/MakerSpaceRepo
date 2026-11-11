import { defineConfig } from "vitest/config";
import { coveragePlugins } from "./config/js_coverage";

// Unit tests for pure functions in app/javascript. Browser behaviour is
// covered by the Capybara system specs; this is only for logic that needs no DOM.
// With JS_COVERAGE=1 app/javascript is instrumented as in the browser build and
// the counters are written to tmp/js-coverage (see config/js_coverage.ts).
export default defineConfig(async ({ mode }) => ({
  plugins: await coveragePlugins(mode),
  test: {
    environment: "node",
    setupFiles: ["spec/javascript/setup.js"],
    globalSetup: ["spec/javascript/global_setup.js"],
    // stubs and fake timers from one example never reach the next
    unstubGlobals: true,
    restoreMocks: true,
    include: ["spec/javascript/**/*.test.{js,ts}"],
    // @fullcalendar/rrule reads the rrule package's named exports, which Node
    // only exposes when the plugin is bundled by Vite like the browser build.
    server: { deps: { inline: ["@fullcalendar/rrule"] } },
  },
}));
