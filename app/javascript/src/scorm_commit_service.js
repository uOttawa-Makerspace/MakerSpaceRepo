import { csrfHeaders, csrfParam, csrfToken } from "./csrf";

// sendBeacon queues at most about 64 KiB per page (all pending beacons together),
// and returns false past that: the data is not sent, silently. Stay well under it.
const BEACON_LIMIT_BYTES = 60 * 1024;

// scorm-again's HTTP service for commits to this app (settings.httpService).
// Every commit is an application/json body to scorm_commit, whose route asks for
// JSON: that is the legacy JSON exemption (ApplicationController#legacy_json_request?),
// so Rails does not check a token on it. What protects them is the media type:
// another site can only send application/json after a CORS preflight, which only
// the origins in lib/cors_origins.rb pass (and the session cookie is SameSite=Lax).
// The token is sent anyway (header, and a body field on the beacon, which cannot
// carry headers), for when that exemption goes.
// - Regular commits: a synchronous XHR, as scorm-again's own SCORM-compliant
//   service does (the SCO learns whether the commit worked).
// - The terminate commit (immediate: the page may be closing): a beacon, which the
//   browser delivers even as the page goes away. scorm-again's own beacon is
//   text/plain, which Rails does not parse, so the final state was lost. Terminate
//   always sends the whole CMI (suspend_data alone can be 64,000 characters), so
//   when it does not fit the beacon quota, or the browser refuses it, it is a
//   synchronous XHR like a regular commit. (That one is refused by browsers only
//   while the page is already being dismissed; then nothing can carry it.)
//
// commitFailureCode is what the SCO is told when a commit fails: SCORM 2004's
// GENERAL_COMMIT_FAILURE (391) for Scorm2004API, SCORM 1.2's General Exception
// (101, it has no commit-specific code) for Scorm12API.
export class ScormCommitService {
  constructor({ commitFailureCode = 101 } = {}) {
    this.success = { result: "true", errorCode: 0 };
    this.failure = { result: "false", errorCode: commitFailureCode };
  }

  updateSettings() {}

  processHttpRequest(url, params, immediate = false) {
    return immediate ? this.terminate(url, params) : this.post(url, params);
  }

  post(url, params) {
    const xhr = new XMLHttpRequest();
    xhr.open("POST", url, false);
    const headers = csrfHeaders({
      "Content-Type": "application/json;charset=UTF-8",
      Accept: "application/json",
    });
    Object.entries(headers).forEach(([name, value]) => xhr.setRequestHeader(name, value));
    try {
      xhr.send(JSON.stringify(params));
    } catch (e) {
      return this.failure;
    }
    return xhr.status >= 200 && xhr.status <= 299 ? this.success : this.failure;
  }

  terminate(url, params) {
    const body = new Blob([JSON.stringify({ ...params, [csrfParam()]: csrfToken() })], {
      type: "application/json",
    });
    if (body.size <= BEACON_LIMIT_BYTES && navigator.sendBeacon(url, body)) return this.success;

    return this.post(url, params);
  }
}
