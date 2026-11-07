// Date maths in the scripts uses the browser's local zone; pin it so the
// results do not depend on the machine running the tests.
export default function setup() {
  process.env.TZ = "UTC";
}
