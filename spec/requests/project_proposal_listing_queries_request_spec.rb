# frozen_string_literal: true

require "rails_helper"

# The proposal lists (the member's own on /project_proposals/user_projects, and the assigned and completed lists)
# show each proposal's categories, in the order they were added. The categories are loaded once for each list, so
# the number of queries does not grow with the proposals. The counts start at two proposals: with one, the query
# cache can hide a repeated read.
RSpec.describe "Project proposal lists: categories", type: :request do
  include ContentSpecHelpers

  let(:member) { create(:user, :regular_user) }

  def proposals!(count, *traits, user: member)
    Array.new(count) do
      create(:project_proposal, *traits, user: user).tap do |proposal|
        %w[Wood Laser].each { |name| proposal.categories.create!(name: "#{name} #{proposal.id}") }
      end
    end
  end

  # Each row's title and categories, per table.
  def listed
    Nokogiri::HTML(response.body).css("table").map do |table|
      columns = table.css("thead th").map { |th| th.text.squish }
      table.css("tbody tr").map do |row|
        cells = row.css("td").map { |td| td.text.squish }
        [cells[columns.index("Title")], cells[columns.index("Categories")]]
      end
    end
  end

  def row(proposal) = [proposal.title, "Wood #{proposal.id} Laser #{proposal.id}"]

  def queries_for(path)
    get path
    count_queries { get path }
  end

  it "shows a member's pending and approved proposals with their categories in the order they were added" do
    content_login!(member)
    pending = proposals!(1)
    approved = proposals!(1, :approved)

    get user_projects_project_proposals_path

    expect(response).to have_http_status(:ok)
    expect(listed).to eq([pending.map { |p| row(p) }, approved.map { |p| row(p) }])
  end

  it "shows an admin the assigned proposals with their categories" do
    content_sign_in_as(:admin)
    assigned = proposals!(2, :joined, user: create(:user, :regular_user))

    get projects_assigned_project_proposals_path

    expect(listed).to eq([assigned.reverse.map { |p| row(p) }])
  end

  it "runs the same number of queries for two proposals in each of the member's lists as for five" do
    content_login!(member)
    proposals!(2)
    proposals!(2, :approved)
    two = queries_for(user_projects_project_proposals_path)
    proposals!(3)
    proposals!(3, :approved)
    five = queries_for(user_projects_project_proposals_path)

    expect(listed.map(&:size)).to eq([5, 5])
    expect(five).to eq(two)
  end

  it "runs the same number of queries for two completed proposals as for five, for an admin" do
    content_sign_in_as(:admin)
    proposals!(2, :completed, user: create(:user, :regular_user))
    two = queries_for(projects_completed_project_proposals_path)
    proposals!(3, :completed, user: create(:user, :regular_user))
    five = queries_for(projects_completed_project_proposals_path)

    expect(listed.map(&:size)).to eq([5])
    expect(five).to eq(two)
  end
end
