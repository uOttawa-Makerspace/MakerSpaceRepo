import { defineConfig } from "vite";
import RubyPlugin from "vite-plugin-ruby";
import { coveragePlugins } from "./config/js_coverage";

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
