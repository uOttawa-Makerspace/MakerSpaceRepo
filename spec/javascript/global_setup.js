// Date maths in the scripts uses the browser's local zone; pin it so the
// results do not depend on the machine running the tests.
import { globSync, rmSync } from "node:fs";

export default function setup() {
  process.env.TZ = "UTC";
  // a coverage run starts without the unit counters of an earlier run
  if (process.env.JS_COVERAGE === "1") {
    for (const f of globSync("tmp/js-coverage/unit-*.json")) rmSync(f);
  }
}
