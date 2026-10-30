# frozen_string_literal: true

require "rails_helper"

# SCORM commits from the learning-module page (learning_modules_scorm.js with
# src/scorm_commit_service.js), in a real browser with forgery protection on:
# regular commits are a synchronous JSON XHR with X-CSRF-Token; the terminate
# commit is a beacon whose urlencoded body carries the token, so Rails parses
# and CSRF-checks it and the final state is stored (scorm-again's own beacon is
# text/plain, which Rails dropped).
# js_errors: :allow because the iframe's own content is a 500 today (the pinned,
# separate WART D-T02 in learning_area_request_spec: send_blob_stream with :type);
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
end
