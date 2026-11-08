import { defineConfig } from "vite";
import RubyPlugin from "vite-plugin-ruby";

// Line and branch counters for the JS system-spec coverage report. Only the
// test build, and only when JS_COVERAGE=1: the development and production
// builds never load the plugin, so their output is unchanged.
// The plugin is ESM only and this config is loaded as CommonJS, so it is
// imported on demand.
const coveragePlugins = async (mode: string) => {
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

export default defineConfig(async ({ mode }) => ({
  build: {
    sourcemap: false,
  },
  plugins: [RubyPlugin(), ...(await coveragePlugins(mode))],
  css: {
    preprocessorOptions: {
      scss: {
        quietDeps: true,
        silenceDeprecations: ["import", "global-builtin", "color-functions"],
      },
    },
  },
  server: {
    host: "0.0.0.0",
    port: 3036,
    strictPort: true,
    cors: true,
    allowedHosts: true,
    hmr: {
      host: "localhost",
      clientPort: 3036,
    },
    watch: {
      usePolling: true,
      interval: 100,
    },
  },
  optimizeDeps: {
    include: [
      "bootstrap",
      "@popperjs/core",
      "@fullcalendar/core",
      "@fullcalendar/daygrid",
      "@fullcalendar/timegrid",
      "@fullcalendar/interaction",
      "@fullcalendar/rrule",
    ],
  },
}));
