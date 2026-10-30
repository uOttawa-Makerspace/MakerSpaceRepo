# frozen_string_literal: true

require "rails_helper"

# The announcements bar (partials/_announcements, on the home page and the staff
# and admin layouts): the list of announcements a user sees is cached per user
# (AnnouncementsHelper#visible_announcements); the dismiss button_to forms are
# rendered live, because their CSRF tokens belong to the current session.
RSpec.describe "Announcements bar caching", type: :request do
  let(:password) { "asa32A353#" }
  let(:staff) { create(:user, :staff) }
  let!(:for_all) { create(:announcement, public_goal: "all", description: "Hello everyone") }
  let!(:for_staff) { create(:announcement, public_goal: "staff", description: "Staff meeting") }
  let(:store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(store)
    stub_request(:get, %r{\Ahttps://simpli\.events/}).to_return(status: 500)
    stub_request(:post, %r{\Ahttps://[^/]+\.myshopify\.com/}).to_return(status: 500)
  end

  def log_in!(u = staff)
    post login_authentication_path, params: { username_email: u.username, password: password }
    expect(response).to redirect_to(root_path)
  end

  # SQL that selects announcement rows (not the aggregate used for the cache key).
  def announcement_list_queries
    queries = []
    callback = lambda do |*, payload|
      sql = payload[:sql].to_s
      queries << sql if sql.include?('FROM "announcements"') && sql.include?("public_goal")
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries
  end

  def dismiss_forms
    Nokogiri::HTML(response.body).css("form").select { |f| f["action"].to_s.start_with?("/announcements/dismiss") }
  end

  it "the second render of the bar reads the list from the cache, not the announcements table" do
    log_in!
    expect(announcement_list_queries { get root_path }).not_to be_empty
    expect(announcement_list_queries { get root_path }).to be_empty
    expect(response.body).to include("Hello everyone", "Staff meeting")
  end

  it "the dismiss forms are rendered live, with tokens of the current session" do
    log_in!
    get root_path # caches the list
    reset! # another browser, same user: a new session and token
    log_in!
    get root_path
    form = dismiss_forms.find { |f| f["action"].include?("announcement_id=#{for_staff.id}") }
    fields = form.css("input[type='hidden']").to_h { |i| [i["name"], i["value"]] }
    expect { post form["action"], params: fields }.to change(AnnouncementDismiss, :count).by(1)
  end

  it "a dismissal, or a new or edited announcement, shows up at once" do
    log_in!
    get root_path
    AnnouncementDismiss.create!(announcement: for_staff, user: staff)
    create(:announcement, public_goal: "all", description: "Brand new")
    get root_path
    expect(response.body).not_to include("Staff meeting")
    expect(response.body).to include("Brand new", "Hello everyone")
    for_all.update!(description: "Edited text")
    get root_path
    expect(response.body).to include("Edited text")
  end

  it "guests see the public announcements, with a plain close button (no form)" do
    get root_path
    expect(response.body).to include("Hello everyone")
    expect(response.body).not_to include("Staff meeting")
    expect(dismiss_forms).to be_empty
  end

  # A cache hit is the key alone: one aggregate query for the announcements, one for
  # the user's dismissals, and no announcement rows. The role flags (volunteer? is a
  # query) are read once per request, not once per consumer.
  describe "the cost of a hit" do
    def sql_during
      queries = []
      callback = ->(*, payload) { queries << payload[:sql].to_s unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
      queries
    end

    it "is one aggregate query per table, and the flags are read once" do
      log_in!
      get root_path
      sql = sql_during { get root_path }
      expect(sql.grep(/FROM "announcements"/).size).to eq(1)
      expect(sql.grep(/FROM "announcement_dismisses"/).size).to eq(1)
      expect(sql.grep(/FROM "announcements"/).first).to include("MAX(updated_at)")
      expect(sql.grep(/FROM "programs"/).size).to eq(2) # volunteer? and dev_program?, once each
    end

    it "a deleted announcement disappears at once (the newest timestamp alone would not change)" do
      newer = create(:announcement, public_goal: "all", description: "Newest")
      log_in!
      get root_path
      expect(response.body).to include("Hello everyone")
      for_all.destroy!
      get root_path
      expect(response.body).not_to include("Hello everyone")
      expect(response.body).to include(newer.description)
    end
  end
end
