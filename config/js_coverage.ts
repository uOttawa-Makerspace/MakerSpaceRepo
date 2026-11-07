// Line and branch counters for the JS coverage report. Only the test mode, and
// only when JS_COVERAGE=1, so the development and production builds never load
// the plugin and their output is unchanged.
//
// Two runs share this one instrumentation, so their statement maps match and
// nyc can merge their counters from tmp/js-coverage:
// - the instrumented test build that the browser (system) specs load
//   (vite.config.ts);
// - the Vitest unit run (vitest.config.ts), which writes its counters with the
//   "unit-" file-name prefix (spec/javascript/setup.js).
// The plugin is ESM only and the configs are loaded as CommonJS, so it is
// imported on demand.
export const coveragePlugins = async (mode: string) => {
  if (mode !== "test" || process.env.JS_COVERAGE !== "1") return [];
  const { default: istanbul } = await import("vite-plugin-istanbul");
  return [
    istanbul({
      include: "app/javascript/**/*",
      extension: [".js", ".ts"],
      requireEnv: false,
      forceBuildInstrument: true,
    }),
  ];
};
