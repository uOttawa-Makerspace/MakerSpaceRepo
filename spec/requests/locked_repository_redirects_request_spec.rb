# frozen_string_literal: true

require "rails_helper"

# A private repository protected by a password that the caller has not entered: every redirect that turns the
# caller away addresses the repository with the username the request used (or the caller's own), so the Location
# header never carries the owner's username. People who may open the repository are sent to the owner's address.
RSpec.describe "Redirects for a locked private repository", type: :request do
  include ContentSpecHelpers

  let(:owner) { create(:user, :regular_user, username: "quillowner") }
  let(:stranger) { create(:user, :regular_user, username: "wanderer") }
  let(:other) { create(:user, :regular_user) }
  let!(:secret) { create(:repository, :private, owner: owner, title: "Hidden Plans", users: [owner]) }
  let!(:comment) { create(:comment, repository: secret, user: owner, username: owner.username) }

  before { secret.update_columns(password: BCrypt::Password.create("open-sesame")) }

  def location
    response.headers["Location"].to_s
  end

  def expect_owner_not_named
    expect(response).to have_http_status(:redirect)
    expect(location).not_to include(owner.username)
  end

  # Each entry sends one request addressed with a username that is not the owner's.
  def requests
    wrong = "someone-else"
    {
      add_like: -> { post add_like_repository_path(wrong, secret.id) },
      comment_create: -> { post comments_create_path(secret.id), params: { content: "peek" } },
      comment_vote: -> { post comments_vote_path(secret.id), params: { comment_id: comment.id } },
      comment_destroy: -> { delete comments_destroy_path(comment.id) },
      edit: -> { get edit_repository_path(wrong, secret.slug) },
      update: -> { patch repository_path(wrong, secret.slug), params: { repository: { title: "Renamed" } } },
      destroy: -> { delete repository_path(wrong, secret.slug) },
      add_member: lambda {
        patch add_member_repositories_path(wrong),
              params: { repo_owner: { repository_id: secret.id, owner_username: other.username } }
      },
      remove_member: lambda {
        patch remove_member_repositories_path(wrong),
              params: { repo_owner: { repository_id: secret.id, owner_id: other.id } }
      },
      transfer_owner: lambda {
        patch transfer_owner_repositories_path(wrong),
              params: { repo_owner: { repository_id: secret.id, owner_id: other.id } }
      },
      link_to_pp: lambda {
        patch link_to_pp_repositories_path(wrong),
              params: { repo: { repository_id: secret.id, project_proposal_id: "" } }
      }
    }
  end

  it "never names the owner to a guest" do
    requests.each do |name, call|
      call.call
      expect(location).not_to include(owner.username), name.to_s
    end
  end

  it "never names the owner to a signed-in stranger" do
    content_login!(stranger)
    requests.each do |name, call|
      call.call
      expect(response).to have_http_status(:redirect), name.to_s
      expect(location).not_to include(owner.username), name.to_s
    end
  end

  it "keeps the username the request used when the caller is turned away" do
    content_login!(stranger)
    post add_like_repository_path("someone-else", secret.id)
    expect(response).to redirect_to(password_entry_repository_path("someone-else", secret.id))
    patch repository_path("someone-else", secret.slug), params: { repository: { title: "Renamed" } }
    expect(response).to redirect_to(repository_path("someone-else", secret.slug))
  end

  it "uses the caller's own username when the request carries none" do
    content_login!(stranger)
    post comments_create_path(secret.id), params: { content: "peek" }
    expect(response).to redirect_to(password_entry_repository_path(stranger.username, secret.id))
  end

  it "does not change the repository or its comments for the stranger" do
    content_login!(stranger)
    expect { requests.each_value(&:call) }.not_to change { [Comment.count, Repository.count, secret.reload.title] }
  end

  it "turns a stranger away from the makes pages toward the password page" do
    content_login!(stranger)
    get makes_new_path(owner.username, secret.id)
    expect(response).to redirect_to(password_entry_repository_path(owner.username, secret.id))
    post makes_create_path(owner.username, secret.id), params: { secret.title => { title: "x" } }
    expect(response).to redirect_to(password_entry_repository_path(owner.username, secret.id))
    expect(Repository.where(make_id: secret.id)).to be_empty
  end

  it "still sends the owner to the owner's address" do
    content_login!(owner)
    patch add_member_repositories_path("someone-else"),
          params: { repo_owner: { repository_id: secret.id, owner_username: "nobody-here" } }
    expect(response).to redirect_to(repository_path(owner.username, secret.slug))
    post add_like_repository_path(owner.username, secret.id)
    expect(response).to redirect_to(repository_path(owner.username, secret.slug))
  end

  it "sends a stranger who entered the password to the owner's address when an owner-only action is refused" do
    content_login!(stranger)
    post pass_authenticate_repository_path(owner.username, secret.id), params: { password: "open-sesame" }
    patch repository_path("someone-else", secret.slug), params: { repository: { title: "Renamed" } }
    expect(response).to redirect_to(repository_path(owner.username, secret.slug))
    patch link_to_pp_repositories_path("someone-else"),
          params: { repo: { repository_id: secret.id, project_proposal_id: "" } }
    expect(response).to redirect_to(repository_path(owner.username, secret.slug))
  end

  it "sends staff to the owner's address when an owner-only action is refused" do
    content_login!(create(:user, :staff))
    patch add_member_repositories_path("someone-else"),
          params: { repo_owner: { repository_id: secret.id, owner_username: "nobody-here" } }
    expect(response).to redirect_to(repository_path(owner.username, secret.slug))
  end
end
