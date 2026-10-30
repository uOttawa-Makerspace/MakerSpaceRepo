# frozen_string_literal: true

require "rails_helper"

# The home page is fragment-cached per user for 10 minutes. The cached cards
# branch on the viewer's role and programs (staff?, admin?, volunteer?,
# dev_program?), so those flags are part of the key: a role or program change shows
# on the next page view, not after the fragment expires.
RSpec.describe "Home page fragment cache and roles", type: :request do
  let(:password) { "asa32A353#" }
  let!(:user) { create(:user, :regular_user) }

  around do |example|
    # rate_limit captures the controller's cache_store when the class is loaded;
    # load the login controllers before the store is swapped, or they would keep
    # this example's MemoryStore (and its counts) for the rest of the process.
    [SessionsController, SamlIdpController, Api::V1::SessionsController]
    store, caching = ActionController::Base.cache_store, ActionController::Base.perform_caching
    ActionController::Base.cache_store = ActiveSupport::Cache::MemoryStore.new
    ActionController::Base.perform_caching = true
    example.run
  ensure
    ActionController::Base.cache_store = store
    ActionController::Base.perform_caching = caching
  end

  before do
    stub_request(:get, %r{\Ahttps://simpli\.events/}).to_return(status: 500)
    stub_request(:post, %r{\Ahttps://[^/]+\.myshopify\.com/}).to_return(status: 500)
    post login_authentication_path, params: { username_email: user.username, password: password }
    expect(response).to redirect_to(root_path)
  end

  def home
    get root_path
    response.body
  end

  # The hrefs inside the cached "Staff Resources" card (the navbar has its own links).
  def staff_card_links
    card = Nokogiri::HTML(home).css(".home-card").find { |c| c.at_css("h2")&.text == "Staff Resources" }
    card ? card.css("a").map { |a| a["href"] } : []
  end

  it "promotion to staff shows the staff card at once, demotion removes it" do
    expect(home).not_to include("Staff Resources")
    user.change_role!("staff")
    expect(home).to include("Staff Resources")
    expect(response.body).not_to include(admin_settings_path)
    user.change_role!("regular_user")
    expect(home).not_to include("Staff Resources")
  end

  it "promotion to admin shows the admin link at once, demotion to staff removes it" do
    user.change_role!("staff")
    expect(staff_card_links).to include(staff_dashboard_index_path)
    expect(staff_card_links).not_to include(admin_settings_path)
    user.change_role!("admin")
    expect(staff_card_links).to include(admin_settings_path)
    user.change_role!("staff")
    expect(staff_card_links).not_to include(admin_settings_path)
  end

  it "joining the volunteer and development programs swaps their promo for their cards at once" do
    first = home
    expect(first).not_to include("No tasks assigned")
    expect(first).to include(volunteers_path, development_programs_path)
    user.programs.create!(program_type: Program::VOLUNTEER)
    expect(home).to include("No tasks assigned")
    user.programs.create!(program_type: Program::DEV_PROGRAM)
    expect(home).to include("No lessons completed")
  end
end
