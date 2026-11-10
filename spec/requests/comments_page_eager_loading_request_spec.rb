# frozen_string_literal: true

require "rails_helper"

# The repository page reads each comment's author; with Bullet raising under CI=1 a request that rendered
# several comments without loading their users in one query would fail.
RSpec.describe "Repository page comments", type: :request do
  include ContentSpecHelpers

  let(:owner) { create(:user, :regular_user) }
  let!(:repo) { create(:repository, owner: owner, title: "Talky", users: [owner]) }

  it "renders a page of comments by different users without a query per comment" do
    5.times { |i| create(:comment, repository: repo, user: create(:user, :regular_user), content: "COMMENT#{i}") }
    content_login!(owner)

    get repository_path(owner.username, repo.id)

    expect(response).to have_http_status(:ok)
    expect(response.body.scan(/COMMENT\d/).size).to eq(5)
  end
end
