# frozen_string_literal: true

require "rails_helper"

# The subskill page and the module page show the signed-in user's progress on each module: a start button with no
# track, a mark-completed button while in progress, a check once completed. A SCORM module hands the user's saved
# SCORM state to its player. The tracks are read once for the page, not by a query per module.
RSpec.describe "Learning area module tracks on the subskill and module pages", type: :request do
  let(:training) { create(:training) }

  def add_module(title)
    create(:learning_module, training: training, title: title, subskill: "welding")
  end

  def add_scorm_module(title)
    create(:learning_module, :with_scorm_object, training: training, title: title, subskill: "welding").tap do |lm|
      ScormExtractor.extract(lm)
    end
  end

  def page = Nokogiri::HTML(response.body)

  def statuses
    page.css(".border.rounded-3").map do |row|
      if row.at_css("form[action*='/learning_module_track/start']") then "start"
      elsif row.at_css("form[action*='/learning_module_track/completed']") then "mark completed"
      elsif row.at_css(".fa-check-circle") then "completed"
      end
    end
  end

  def player_states
    page.css("iframe[data-cmi]").to_h { |frame| [frame["title"], JSON.parse(frame["data-cmi"])] }
  end

  def track_queries(path)
    sqls = []
    callback = ->(*, payload) { sqls << payload[:sql] if payload[:sql].include?('FROM "learning_module_tracks"') && !payload[:cached] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get path }
    expect(response).to have_http_status(:ok)
    sqls
  end

  it "sends a guest to sign in from both pages" do
    learning_module = add_module("Alpha")

    get subskill_learning_area_index_path("welding")
    expect(CGI.unescape(response.location)).to eq("http://www.example.com/login?back_to=/learning_area/subskill/welding")

    get learning_area_path(learning_module)
    expect(CGI.unescape(response.location)).to eq("http://www.example.com/login?back_to=/learning_area/#{learning_module.id}")
  end

  context "when signed in" do
    let!(:user) { sign_in_as(:regular) }
    let(:other_user) { create(:user, :regular_user) }

    it "offers every module to start when the user has no tracks" do
      add_module("Alpha")
      add_module("Beta")
      add_scorm_module("Packaged")
      create(:learning_module_track, :completed, user: other_user, learning_module: LearningModule.find_by(title: "Alpha"))

      get subskill_learning_area_index_path("welding")

      expect(response).to have_http_status(:ok)
      expect(statuses).to eq(["start", "start"])
      expect(player_states).to eq("Packaged" => {})
    end

    it "shows each module's status and SCORM state for the signed-in user only" do
      done = add_module("Alpha")
      started = add_module("Beta")
      untouched = add_module("Gamma")
      scorm = add_scorm_module("Packaged")
      fresh_scorm = add_scorm_module("Packaged two")
      create(:learning_module_track, :completed, user: user, learning_module: done)
      create(:learning_module_track, user: user, learning_module: started)
      create(:learning_module_track, :completed, user: other_user, learning_module: untouched)
      create(:learning_module_track, user: user, learning_module: scorm, scorm_state: { "cmi.location" => "page-3" })
      create(:learning_module_track, user: other_user, learning_module: fresh_scorm, scorm_state: { "cmi.location" => "theirs" })

      get subskill_learning_area_index_path("welding")

      expect(response).to have_http_status(:ok)
      expect(statuses).to eq(["completed", "mark completed", "start"])
      expect(player_states).to eq("Packaged" => { "cmi.location" => "page-3" }, "Packaged two" => {})
    end

    it "shows the same status and SCORM state on the module page" do
      done = add_module("Alpha")
      started = add_module("Beta")
      untouched = add_module("Gamma")
      scorm = add_scorm_module("Packaged")
      create(:learning_module_track, :completed, user: user, learning_module: done)
      create(:learning_module_track, user: user, learning_module: started)
      create(:learning_module_track, :completed, user: other_user, learning_module: untouched)
      create(:learning_module_track, user: user, learning_module: scorm, scorm_state: { "cmi.location" => "page-3" })

      shown = [done, started, untouched].map do |learning_module|
        get learning_area_path(learning_module)
        statuses.sole
      end
      expect(shown).to eq(["completed", "mark completed", "start"])

      get learning_area_path(scorm)
      expect(player_states).to eq("Packaged" => { "cmi.location" => "page-3" })
    end

    it "does not look up the user's tracks module by module" do
      add_module("Alpha")
      add_scorm_module("Packaged")
      one_each = track_queries(subskill_learning_area_index_path("welding")).size
      add_module("Beta")
      add_module("Gamma")
      add_scorm_module("Packaged two")

      expect(track_queries(subskill_learning_area_index_path("welding")).size).to eq(one_each)
    end
  end
end
