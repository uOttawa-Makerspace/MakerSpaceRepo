import { defineConfig } from "vite";
import RubyPlugin from "vite-plugin-ruby";

export default defineConfig({
  plugins: [RubyPlugin()],
  optimizeDeps: {
    include: [
      "@fullcalendar/core",
      "@fullcalendar/daygrid",
      "@fullcalendar/timegrid",
      "@fullcalendar/interaction",
      "@fullcalendar/rrule",
    ],
  },
  build: {
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes("node_modules")) {
            // Bootstrap into its own chunk — prevents duplication across
            // header, application, and other entrypoints
            if (id.includes("bootstrap")) {
              return "bootstrap";
            }

            // FullCalendar is large (~230kB combined) and only used on
            // calendar pages — keep it in a separate lazy-loadable chunk
            if (id.includes("@fullcalendar") || id.includes("rrule")) {
              return "fullcalendar";
            }

            // jQuery used by DataTables — isolate so pages without tables
            // don't pay the cost
            if (id.includes("jquery")) {
              return "jquery";
            }

            // DataTables
            if (id.includes("datatables") || id.includes("dataTables")) {
              return "datatables";
            }

            // Everything else from node_modules into a shared vendor chunk
            return "vendor";
          }
        },
      },
    },
  },
});
