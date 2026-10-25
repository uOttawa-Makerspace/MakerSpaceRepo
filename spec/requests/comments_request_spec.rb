# frozen_string_literal: true

require "rails_helper"

# Chunk 16: CommentsController (repository comments + up/down votes).
#
# Gates: `signed_in` on every action. There is no ownership or visibility check
# on create/vote (private repositories, self-voting); destroy is
# author-or-admin only.
RSpec.describe "Comments (HTTP contract)", type: :request do
  include ContentSpecHelpers

  let(:owner) { create(:user, :regular_user) }
  let(:author) { create(:user, :regular_user) }
  let(:voter) { create(:user, :regular_user) }
  let!(:repo) { create(:repository, owner: owner, title: "Talky", users: [owner]) }
  let(:anchor_path) { repository_path(owner.username, repo.id, anchor: "repo-comments") }

  def post_comment(content, repository: repo)
    post comments_create_path(repository.id), params: { content: content }
  end

  def vote(comment, downvote: nil, repository: repo)
    post comments_vote_path(repository.id),
         params: { comment_id: comment.id, downvote: downvote }.compact
  end

  describe "POST create" do
    it "sends a guest to login and persists nothing" do
      expect { post_comment("hi") }.not_to change(Comment, :count)
      expect(response).to redirect_to(login_path(back_to: "/comments/#{repo.id}"))
    end

    it "persists the comment under the current user and redirects to the repo comments anchor" do
      content_login!(author)
      expect { post_comment("Nice work") }.to change(Comment, :count).by(1)
      c = Comment.last
      expect([c.content, c.user_id, c.username, c.repository_id, c.upvote])
        .to eq(["Nice work", author.id, author.username, repo.id, 0])
      expect(response).to redirect_to(anchor_path)
      expect(flash[:notice]).to eq("The comment was successfully posted.")
    end

    it "ignores a user_id / username param (only :content is permitted)" do
      content_login!(author)
      post comments_create_path(repo.id), params: { content: "x", user_id: owner.id, username: "admin" }
      expect(Comment.last.user_id).to eq(author.id)
      expect(Comment.last.username).to eq(author.username)
    end

    it "rejects blank and 1001-character comments with the length alert" do
      content_login!(author)
      [" ", "a" * 1001].each do |bad|
        expect { post_comment(bad) }.not_to change(Comment, :count)
        expect(response).to redirect_to(anchor_path)
        expect(flash[:alert]).to start_with("An error occured while trying to post the comment")
      end
      expect { post_comment("a" * 1000) }.to change(Comment, :count).by(1)
    end

    it "stores markup verbatim (escaping is a view concern, see the show spec)" do
      content_login!(author)
      post_comment("<script>alert(1)</script>")
      expect(Comment.last.content).to eq("<script>alert(1)</script>")
      get repository_path(owner.username, repo.id)
      expect(response.body).not_to include("<script>alert(1)</script>")
    end

    it "lets anyone comment on a private repository without its password (D-C17)" do
      secret = create(:repository, :private, owner: owner, title: "Hush", users: [owner])
      content_login!(author)
      # WART(D-C17): create does not run check_auth; the password gate is only on show/download
      expect { post_comment("peek", repository: secret) }.to change { secret.comments.count }.by(1)
    end

    it "404s for an unknown or soft-deleted repository" do
      content_login!(author)
      repo.update_columns(deleted: true)
      post_comment("hi")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE destroy" do
    let!(:comment) { create(:comment, repository: repo, user: author, username: author.username) }

    it "sends a guest to login and keeps the comment" do
      expect { delete comments_destroy_path(comment.id) }.not_to change(Comment, :count)
      expect(response).to have_http_status(:found)
      expect(response.location).to include("/login")
    end

    it "refuses another regular user: 'Something went wrong', comment kept" do
      content_login!(voter)
      expect { delete comments_destroy_path(comment.id) }.not_to change(Comment, :count)
      expect(flash[:alert]).to eq("Something went wrong")
      expect(response).to redirect_to(repository_path(owner.username, repo.id))
    end

    it "refuses the repository owner (not the author) and staff" do
      content_login!(owner)
      expect { delete comments_destroy_path(comment.id) }.not_to change(Comment, :count)
      content_sign_in_as(:staff)
      expect { delete comments_destroy_path(comment.id) }.not_to change(Comment, :count)
    end

    it "lets the author delete (and cascades its votes)" do
      create(:upvote, comment: comment, user: voter)
      content_login!(author)
      expect { delete comments_destroy_path(comment.id) }
        .to change(Comment, :count).by(-1).and change(Upvote, :count).by(-1)
      expect(flash[:notice]).to eq("Comment deleted succesfully")
    end

    it "lets an admin delete anyone's comment" do
      content_sign_in_as(:admin)
      expect { delete comments_destroy_path(comment.id) }.to change(Comment, :count).by(-1)
    end

    it "500s for an unknown comment (the redirect dereferences nil) (D-C18)" do
      content_login!(author)
      # WART(D-C18): destroy of a missing comment flashes then calls comment.repository on nil
      delete comments_destroy_path(0)
      expect(response).to have_http_status(:internal_server_error)
    end
  end

  describe "POST vote" do
    let!(:comment) { create(:comment, repository: repo, user: author, username: author.username) }

    it "sends a guest to login and records nothing" do
      expect { vote(comment) }.not_to change(Upvote, :count)
      expect(response.location).to include("/login")
    end

    it "upvote: +1 on the comment counter, +2 reputation for the author, notice, redirect" do
      content_login!(voter)
      expect { vote(comment) }.to change(Upvote, :count).by(1)
      expect(comment.reload.upvote).to eq(1)
      expect(author.reload.reputation).to eq(2)
      expect(flash[:notice]).to eq("Successfully upvoted comment")
      expect(response).to redirect_to(repository_path(owner.username, repo.id, anchor: "repo-comments"))
    end

    it "downvote: -1 counter, -2 reputation" do
      content_login!(voter)
      vote(comment, downvote: "t")
      expect(comment.reload.upvote).to eq(-1)
      expect(author.reload.reputation).to eq(-2)
      expect(Upvote.last.downvote).to be(true)
      expect(flash[:notice]).to eq("Successfully downvoted comment")
    end

    it "voting the same way twice toggles the vote off, reversing counter and reputation" do
      content_login!(voter)
      vote(comment)
      expect { vote(comment) }.to change(Upvote, :count).by(-1)
      expect(comment.reload.upvote).to eq(0)
      expect(author.reload.reputation).to eq(0)
      expect(flash[:notice]).to eq("Successfully removed upvote")
    end

    it "flipping upvote to downvote swings the counter by 2 and the reputation by 4" do
      content_login!(voter)
      vote(comment)
      vote(comment, downvote: "t")
      expect(comment.reload.upvote).to eq(-1)
      expect(author.reload.reputation).to eq(-2)
      expect(Upvote.where(comment: comment, user: voter).count).to eq(1)
    end

    it "removing a downvote restores counter and reputation" do
      content_login!(voter)
      vote(comment, downvote: "t")
      vote(comment, downvote: "t")
      expect(flash[:notice]).to eq("Successfully removed downvote")
      expect(comment.reload.upvote).to eq(0)
      expect(author.reload.reputation).to eq(0)
    end

    it "anything other than downvote=t counts as an upvote" do
      content_login!(voter)
      vote(comment, downvote: "true")
      expect(Upvote.last.downvote).to be(false)
    end

    it "lets the author vote on their own comment and farm reputation (D-C19)" do
      content_login!(author)
      vote(comment)
      # WART(D-C19): no self-vote guard
      expect(comment.reload.upvote).to eq(1)
      expect(author.reload.reputation).to eq(2)
    end

    it "accepts a comment_id from a different repository than the :id segment (D-C20)" do
      other = create(:repository, owner: owner, title: "Other", users: [owner])
      content_login!(voter)
      # WART(D-C20): vote never checks comment.repository == :id; the :id only drives the redirect
      post comments_vote_path(other.id), params: { comment_id: comment.id }
      expect(comment.reload.upvote).to eq(1)
      expect(response).to redirect_to(repository_path(owner.username, other.id, anchor: "repo-comments"))
    end

    it "404s for an unknown comment or repository" do
      content_login!(voter)
      post comments_vote_path(repo.id), params: { comment_id: 0 }
      expect(response).to have_http_status(:not_found)
      post comments_vote_path(0), params: { comment_id: comment.id }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "comments on the repository page" do
    # N+1 pinned: see defects D-PERF-C02
    it "orders by score by default and by recency with comment_filter=newest; 5 per page", skip_bullet: true do
      low = create(:comment, repository: repo, user: author, content: "LOWCOMMENT", upvote: 0, created_at: 1.day.ago)
      high = create(:comment, repository: repo, user: author, content: "HIGHCOMMENT", upvote: 9, created_at: 2.days.ago)
      get repository_path(owner.username, repo.id)
      expect(response.body.index("HIGHCOMMENT")).to be < response.body.index("LOWCOMMENT")
      get repository_path(owner.username, repo.id, comment_filter: "newest")
      expect(response.body.index("LOWCOMMENT")).to be < response.body.index("HIGHCOMMENT")
      6.times { |i| create(:comment, repository: repo, user: author, content: "FILLER#{i}", upvote: 5) }
      get repository_path(owner.username, repo.id)
      expect(response.body.scan(/FILLER\d|HIGHCOMMENT|LOWCOMMENT/).size).to eq(5)
    end
  end
end
