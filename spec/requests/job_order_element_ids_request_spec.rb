# frozen_string_literal: true

require "rails_helper"

# The staff job order page carries two comment fields (quote modal and decline
# form); each needs its own id so labels and scripts reach the right one.
RSpec.describe "Job order page element ids", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:admin) { create(:user, :admin) }

  before do
    seed_job_statuses!
    seed_job_order_message!
    ActionMailer::Base.deliveries.clear
  end

  def log_in_via_form!(user)
    post login_authentication_path, params: { username_email: user.username, password: "asa32A353#" }
  end

  it "gives the decline form comment field its own id, label and unchanged param name" do
    order = make_job_order!(owner: owner, status_key: :staff_approval)
    order.job_tasks.create!(title: "Task #1")
    log_in_via_form!(admin)

    get job_order_path(order)

    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    ids = doc.css("[id]").map { |n| n["id"] }
    expect(ids.select { |id| id == "user_comments" }.size).to be <= 1
    expect(ids.tally.select { |_, n| n > 1 }.keys & %w[user_comments decline_user_comments]).to be_empty

    field = doc.at_css("#decline-modal input#decline_user_comments")
    expect(field["name"]).to eq("user_comments")
    expect(doc.at_css("#decline-modal label[for='decline_user_comments']")).to be_present
  end
end
