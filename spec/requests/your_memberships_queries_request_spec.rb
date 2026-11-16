# frozen_string_literal: true

require "rails_helper"

# /memberships/your_memberships lists the member's active memberships and their paid history, each with its tier's
# title. The tiers are loaded once for each list, so the number of queries does not grow with the memberships. The
# tiers here are hidden, so the purchase cards stay the same while the lists grow.
RSpec.describe "Your memberships: queries", type: :request do
  let(:member) { create(:user, :regular_user) }

  def log_in!(user)
    post login_authentication_path, params: { username_email: user.username, password: "asa32A353#" }
    expect(response).to redirect_to(root_path)
  end

  # Each membership with its own tier, so no read of one is answered from the query cache. Every other one has ended.
  def memberships!(count)
    Array.new(count) do |i|
      tier = create(:membership_tier, hidden: true, title_en: "Tier #{Membership.count} Membership")
      ends = i.even? ? 20.days.from_now : 2.days.ago
      create(:membership, user: member, membership_tier: tier, start_date: ends - 30.days, end_date: ends)
    end
  end

  def page
    Nokogiri::HTML(response.body)
  end

  def history_rows = page.css(".col-lg-4 tbody tr").map { |row| row.css("td").map { |td| td.text.squish } }

  def queries_for(path)
    get path
    count_queries { get path }
  end

  it "shows the active memberships and the paid history with each tier's title" do
    log_in!(member)
    current, ended = memberships!(2)

    get your_memberships_memberships_path

    expect(response).to have_http_status(:ok)
    expect(page.css(".alert-success").text).to include("Tier 0")
    expect(history_rows.map { |cells| [cells[0], cells[2]] }).to contain_exactly(["Tier 0", "Active"], ["Tier 1", "Expired"])
    expect([current, ended]).to all(be_persisted)
  end

  it "runs the same number of queries for two memberships as for five" do
    log_in!(member)
    memberships!(2)
    two = queries_for(your_memberships_memberships_path)
    memberships!(3)
    five = queries_for(your_memberships_memberships_path)

    expect(history_rows.size).to eq(5)
    expect(five).to eq(two)
  end
end
