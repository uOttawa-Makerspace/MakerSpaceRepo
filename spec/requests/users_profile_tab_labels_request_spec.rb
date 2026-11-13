# frozen_string_literal: true

require "rails_helper"

# Every aria-labelledby on the profile page must name an element that exists.
RSpec.describe "Profile page tab labels", type: :request do
  def dangling_labels
    doc = Nokogiri::HTML(response.body)
    ids = doc.css("[id]").map { |n| n["id"] }
    doc.css("[aria-labelledby]").flat_map { |n| n["aria-labelledby"].split } - ids
  end

  def log_in_via_form!(user)
    post login_authentication_path, params: { username_email: user.username, password: "asa32A353#" }
  end

  it "resolves every aria-labelledby for the owner" do
    owner = create(:user, :regular_user)
    log_in_via_form!(owner)

    get user_path(owner.username)

    expect(response).to have_http_status(:ok)
    expect(dangling_labels).to be_empty
    expect(response.body).to include('aria-labelledby="programs-tab"')
  end

  it "resolves every aria-labelledby for a visitor viewing another profile" do
    owner = create(:user, :regular_user)
    visitor = create(:user, :regular_user)
    log_in_via_form!(visitor)

    get user_path(owner.username)

    expect(response).to have_http_status(:ok)
    expect(dangling_labels).to be_empty
  end

  it "resolves every aria-labelledby for an admin viewing a staff profile" do
    admin = create(:user, :admin)
    log_in_via_form!(admin)

    get user_path(admin.username)

    expect(response).to have_http_status(:ok)
    expect(dangling_labels).to be_empty
    expect(response.body).to include('aria-labelledby="admin-tab"')
  end

  it "resolves every aria-labelledby for a staff member viewing another profile" do
    staff = create(:user, :staff)
    other = create(:user, :regular_user)
    log_in_via_form!(staff)

    get user_path(other.username)

    expect(response).to have_http_status(:ok)
    expect(dangling_labels).to be_empty
  end

  it "keeps the profile tab list out of another tab list" do
    admin = create(:user, :admin)
    log_in_via_form!(admin)

    get user_path(admin.username)

    doc = Nokogiri::HTML(response.body)
    expect(doc.css("#myTab [role=tablist]").size).to eq(1)
    expect(doc.css("[role=tablist] [role=tablist]")).to be_empty
  end
end
