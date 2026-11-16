# frozen_string_literal: true

require "rails_helper"

# The UserWay accessibility widget loads for visitors and members on every layout. Staff and
# admins see member records, so for them no page loads it, and every page carries a
# Turbo-tracked marker instead: a Turbo visit made before they signed in starts a fresh page.
RSpec.describe "The accessibility widget by viewer", type: :request do
  let(:password) { "asa32A353#" }

  before { block_external_http! }

  def login!(user)
    post login_authentication_path, params: { username_email: user.username, password: password }
  end

  def html
    Nokogiri::HTML(response.body)
  end

  def widget_count
    html.css("[data-controller=userway]").size
  end

  def marker_count
    html.css("head meta[name=accessibility-widget][content=off][data-turbo-track=reload]").size
  end

  def tracked_head_tags
    html.css("head [data-turbo-track=reload]").map(&:to_html)
  end

  def expect_widget
    expect(response).to have_http_status(:ok)
    expect(widget_count).to eq(1)
    expect(marker_count).to eq(0)
  end

  def expect_no_widget
    expect(response).to have_http_status(:ok)
    expect(widget_count).to eq(0)
    expect(response.body).not_to include("cdn.userway.org")
    expect(marker_count).to eq(1)
  end

  # Page name => [layout, the path, who may open it].
  {
    "home page" => ["application", -> { root_path }, %i[guest member]],
    "orders" => ["application", -> { orders_path }, %i[member]],
    "a profile" => ["application", -> { user_path(create(:user, :regular_user).username) }, %i[guest member]],
    "profile settings" => ["setting", -> { settings_profile_path }, %i[member]],
    "a licence" => ["license", -> { licenses_cca_path }, %i[guest member]],
    "getting started" => ["getting_started", -> { getting_started_sua_path }, %i[guest member]]
  }.each do |page_name, (layout, path, viewers)|
    viewers.each do |viewer|
      it "#{page_name} (#{layout} layout): a #{viewer} gets the widget" do
        login!(create(:user, :regular_user)) if viewer == :member
        get instance_exec(&path)

        expect_widget
      end
    end

    %i[staff admin].each do |role|
      it "#{page_name} (#{layout} layout): #{role} get no widget and the marker" do
        login!(create(:user, role))
        get instance_exec(&path)

        expect_no_widget
      end
    end
  end

  it "an admin page (admin_area layout): an admin gets no widget and the marker" do
    login!(create(:user, :admin))
    get admin_announcements_path

    expect_no_widget
  end

  it "a staff page (staff_area layout): staff get no widget and the marker" do
    login!(create(:user, :staff))
    get printer_issues_path

    expect_no_widget
  end

  it "the kiosk page: staff get no widget and the marker" do
    space = create(:space)
    login!(create(:user, :staff, space: space)) # staff use only the kiosk of a space they are assigned to
    get kiosk_path(space)

    expect_no_widget
  end

  # A Turbo visit between two pages stays in one document only while they track the same head tags.
  it "every layout tracks the same head tags for the same viewer" do
    login!(create(:user, :admin))
    signatures = [root_path, admin_announcements_path, printer_issues_path, settings_profile_path,
                  licenses_cca_path, getting_started_sua_path, kiosk_path(create(:space))].map do |path|
      get path
      expect(response).to have_http_status(:ok)
      tracked_head_tags
    end

    expect(signatures.uniq.size).to eq(1)
  end
end
