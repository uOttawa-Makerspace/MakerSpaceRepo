import { showToast } from "./toast";

const FALLBACK =
  "The change could not be saved. Reload the page and try again.";

// An error whose message came from the server's JSON `error` (already
// translated, and carrying the reference code when the failure was unexpected).
export class ServerError extends Error {}

/** @returns {string} */
function genericMessage() {
  const element = /** @type {HTMLElement | null} */ (
    document.querySelector("[data-request-failed]")
  );
  return element?.dataset.requestFailed || FALLBACK;
}

async function readBody(response) {
  try {
    return await response.json();
  } catch {
    return null;
  }
}

// Throws a ServerError carrying the server's `error` when the response is not
// OK. A body without one (an HTML error page, a proxy error) gets the page's
// generic text, with the request id's first characters as the reference when
// the response carries one.
export async function rejectFailedResponse(response) {
  if (response.ok) return;
  const message = (await readBody(response))?.error;
  if (message) throw new ServerError(message);
  const id = response.headers?.get("X-Request-Id");
  throw new ServerError(
    id ? `${genericMessage()} [${id.slice(0, 8)}]` : genericMessage(),
  );
}

// Shows the failure as an error toast: the server's message for a ServerError,
// the generic text for anything else (a dropped connection). A ServerError is a refusal the user is told
// about, so only other errors are logged.
export function showRequestFailure(error) {
  if (!(error instanceof ServerError)) console.error(error);
  showToast(error instanceof ServerError ? error.message : genericMessage(), {
    type: "error",
  });
}
