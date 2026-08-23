import { defineConfig } from "vite";
import RubyPlugin from "vite-plugin-ruby";

export default defineConfig({
  build: {
    sourcemap: false,
  },
  plugins: [RubyPlugin()],
  css: {
    preprocessorOptions: {
      scss: {
        quietDeps: true,
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
});
