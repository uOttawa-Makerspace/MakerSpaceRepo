# frozen_string_literal: true

require "rails_helper"

# SCORM commits from the learning-module page (learning_modules_scorm.js with
# src/scorm_commit_service.js), in a real browser with forgery protection on:
# every commit is an application/json body. Regular commits are a synchronous XHR
# with X-CSRF-Token. The terminate commit is a beacon (JSON; scorm-again's own is
# text/plain, which Rails dropped) unless the whole CMI (suspend_data alone can be
# 64,000 characters, more once JSON-escaped) exceeds sendBeacon's ~64 KiB quota:
# then it is a synchronous XHR, so the final state is stored in full instead of
# being silently lost. A failed commit tells the SCO its API's own error code.
# js_errors: :allow because the iframe's own content is a 500 today (the pinned,
# separate pinned example in learning_area_request_spec: send_blob_stream with :type);
# the commits under test go from the parent page's SCORM API.
RSpec.describe "SCORM commits", type: :system, js_errors: :allow do
  let(:user) { create(:user, :volunteer_with_dev_program) }
  let!(:scorm) do
    create(:learning_module, :with_scorm_object, training: create(:training), title: "Scorm module").tap do |lm|
      ScormExtractor.extract(lm)
    end
  end

  def track_state
    LearningModuleTrack.find_by(user: user, learning_module: scorm)&.reload&.scorm_state || {}
  end

  def wait_for_state(key, value)
    Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until track_state[key] == value }
  end

  before do
    log_in_as(user)
    visit learning_area_path(scorm)
    expect(page).to have_css("iframe[data-learning-module-id='#{scorm.id}']")
    wait = Capybara.default_max_wait_time
    Timeout.timeout(wait) { sleep 0.05 until page.evaluate_script("typeof window.API_1484_11") == "object" }
  end

  it "a regular Commit is stored" do
    result = page.evaluate_script(<<~JS)
      (() => {
        const api = window.API_1484_11;
        api.Initialize("");
        api.SetValue("cmi.location", "page-3");
        return api.Commit("");
      })()
    JS
    expect(result).to eq("true")
    wait_for_state("cmi.location", "page-3")
  end

  it "the terminate commit (a beacon) is stored too" do
    page.execute_script(<<~JS)
      const api = window.API_1484_11;
      api.Initialize("");
      api.SetValue("cmi.location", "last-page");
      api.SetValue("cmi.completion_status", "completed");
      api.Terminate("");
    JS
    wait_for_state("cmi.location", "last-page")
    expect(track_state["cmi.completion_status"]).to eq("completed")
  end

  # Records sendBeacon calls (content type and size) while still sending them.
  def spy_on_beacons
    page.execute_script(<<~JS)
      window.__beacons = [];
      const original = navigator.sendBeacon.bind(navigator);
      navigator.sendBeacon = (url, blob) => {
        window.__beacons.push({ type: blob.type, size: blob.size });
        return original(url, blob);
      };
    JS
  end

  def beacons
    page.evaluate_script("window.__beacons")
  end

  it "a small terminate commit is one application/json beacon" do
    spy_on_beacons
    page.execute_script(<<~JS)
      const api = window.API_1484_11;
      api.Initialize("");
      api.SetValue("cmi.location", "small");
      api.Terminate("");
    JS
    wait_for_state("cmi.location", "small")
    expect(beacons.map { |b| b["type"] }).to eq(["application/json"])
  end

  it "a sendBeacon that throws (SecurityError for the Blob type) falls back to the synchronous XHR" do
    page.execute_script(<<~JS)
      navigator.sendBeacon = () => { throw new DOMException("blocked", "SecurityError"); };
      const api = window.API_1484_11;
      api.Initialize("");
      api.SetValue("cmi.location", "after-throw");
      api.Terminate("");
    JS
    wait_for_state("cmi.location", "after-throw")
  end

  it "a terminate commit too big for the beacon quota is sent as a synchronous XHR and stored in full" do
    spy_on_beacons
    big = %("quoted"\n) * 6_400 # 64,000 characters, ~88 KB once JSON-escaped
    page.execute_script(<<~JS)
      const api = window.API_1484_11;
      api.Initialize("");
      api.SetValue("cmi.suspend_data", #{big.to_json});
      api.SetValue("cmi.location", "big");
      api.Terminate("");
    JS
    wait_for_state("cmi.location", "big")
    expect(track_state["cmi.suspend_data"]).to eq(big)
    expect(beacons).to be_empty
  end

  # scorm-again raises the service's errorCode on the API (throwSCORMError); for
  # SCORM 2004 it then resets GetLastError to 0 itself (Commit is checkTerminated),
  # so the raised code is what is observable, and the "false" the SCO gets back.
  it "a failed commit raises its API's own code: 391 (GENERAL_COMMIT_FAILURE) for SCORM 2004, 101 for SCORM 1.2" do
    page.execute_script("XMLHttpRequest.prototype.send = function () { throw new Error('offline'); };")
    result = page.evaluate_script(<<~JS)
      (() => {
        const raised = { v2004: [], v12: [] };
        const v2004 = window.API_1484_11;
        const v12 = window.API;
        [[v2004, "v2004"], [v12, "v12"]].forEach(([api, name]) => {
          const original = api.throwSCORMError.bind(api);
          api.throwSCORMError = (element, code, ...rest) => { raised[name].push(code); return original(element, code, ...rest); };
        });
        v2004.Initialize("");
        v2004.SetValue("cmi.location", "x");
        v12.LMSInitialize("");
        v12.LMSSetValue("cmi.core.lesson_location", "x");
        return { returned: [v2004.Commit(""), v12.LMSCommit("")], raised };
      })()
    JS
    expect(result["returned"]).to eq(%w[false false])
    expect(result["raised"]).to eq("v2004" => [391], "v12" => [101])
  end
end
