import { defineConfig } from "vite";
import RubyPlugin from "vite-plugin-ruby";

export default defineConfig({
  build: {
    sourcemap: false, // Ensures we don't ship multi-megabyte .map files
  },
  plugins: [RubyPlugin()],
  server: {
    host: "0.0.0.0",
    port: 3036,
    strictPort: true,
    hmr: {
      host: "localhost",
      clientPort: 3036,
    },
  },
  optimizeDeps: {
    include: [
      "@fullcalendar/core",
      "@fullcalendar/daygrid",
      "@fullcalendar/timegrid",
      "@fullcalendar/interaction",
      "@fullcalendar/rrule",
    ],
  },
});
