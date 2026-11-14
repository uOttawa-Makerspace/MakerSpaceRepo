# frozen_string_literal: true

require "rails_helper"

# The UserWay accessibility widget is kept on every page (owner decision until
# the site is accessibility-compliant), so each app layout renders it once.
RSpec.describe "The accessibility widget on every layout", type: :request do
  let(:password) { "asa32A353#" }

  before { block_external_http! }

  def login!(user)
    post login_authentication_path, params: { username_email: user.username, password: password }
  end

  def widget_count
    Nokogiri::HTML(response.body).css("[data-controller=userway]").size
  end

  def tracked_head_tags
    Nokogiri::HTML(response.body).css("head [data-turbo-track=reload]").map(&:to_html)
  end

  # A Turbo visit between two pages stays in one document only while they track the same head tags.
  it "every layout tracks the same head tags" do
    login!(create(:user, :admin))
    signatures = [root_path, admin_announcements_path, printer_issues_path, settings_profile_path,
                  licenses_cca_path, getting_started_sua_path, kiosk_path(create(:space))].map do |path|
      get path
      expect(response).to have_http_status(:ok)
      tracked_head_tags
    end

    expect(signatures.uniq.size).to eq(1)
  end

  it "application layout (home page)" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(widget_count).to eq(1)
  end

  it "admin_area layout" do
    login!(create(:user, :admin))
    get admin_announcements_path

    expect(response).to have_http_status(:ok)
    expect(widget_count).to eq(1)
  end

  it "staff_area layout" do
    login!(create(:user, :staff))
    get announcements_path

    expect(response).to have_http_status(:ok)
    expect(widget_count).to eq(1)
  end
end
