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
