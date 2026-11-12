# frozen_string_literal: true

require "rails_helper"

# Chunk 16: RepositoriesController (HTTP contract).
#
# Gates: `signed_in` for everything except show/download_files; set_repository
# (id OR slug OR title, soft-deleted rows excluded by Repository's
# default_scope); check_auth (show/download_files: admin, staff, the owner by
# username, or a password the session already passed); check_ownership
# (edit/update: admin, the owner or a member of repository.users; destroy and member management: admin or the owner).
#
# There is no GitHub integration in this controller: the `github` / `github_url`
# columns are only copied by MakesController (see makes_request_spec.rb).
RSpec.describe "Repositories (HTTP contract)", type: :request do
  include ContentSpecHelpers

  let(:owner) { create(:user, :regular_user) }
  let(:stranger) { create(:user, :regular_user) }
  let!(:repo) do
    create(:repository, owner: owner, title: "Laser Lamp", users: [owner])
  end

  def repo_path(r = repo, user_username: r.user_username)
    repository_path(user_username, r.slug)
  end

  def valid_params(title: "Brand New Thing", **extra)
    {
      repository: {
        title: title,
        description: "desc",
        share_type: "public",
        license: "Creative Commons - Attribution",
        photos_attributes: { "0" => { image: content_png_upload } }
      }.merge(extra)
    }
  end

  describe "GET show" do
    it "renders a public repository for a guest" do
      get repo_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Laser Lamp")
    end

    it "renders a repository with several photos without per-photo attachment queries" do
      create(:photo, repository: repo)
      create(:photo, repository: repo)
      queries = []
      counter = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?('FROM "active_storage_attachments"') }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get repo_path }
      expect(response).to have_http_status(:ok)
      expect(queries.size).to eq(1)
    end

    it "renders the edit form for a repository with several photos" do
      create(:photo, repository: repo)
      content_login!(owner)
      get edit_repository_path(repo.user_username, repo.slug)
      expect(response).to have_http_status(:ok)
    end

    it "writes the repo into the recently_viewed cookie" do
      get repo_path
      cookie = JSON.parse(CGI.unescape(response.cookies["recently_viewed"]))
      expect(cookie).to eq({ "/#{owner.username}/#{repo.id}" => "Laser Lamp" })
    end

    it "keeps the five most recently viewed repositories, newest first, without duplicates" do
      repos = Array.new(6) { |i| create(:repository, owner: owner, title: "Viewed #{i}", users: [owner]) }
      repos.each { |r| get repo_path(r) }
      get repo_path(repos[3])
      links = JSON.parse(CGI.unescape(cookies[:recently_viewed])).keys
      expect(links).to eq([3, 5, 4, 2, 1].map { |i| "/#{owner.username}/#{repos[i].id}" })
    end

    it "starts the recently_viewed cookie afresh when it holds JSON that is not a list of links" do
      cookies[:recently_viewed] = "[1, 2]"
      get repo_path
      expect(JSON.parse(CGI.unescape(response.cookies["recently_viewed"]))).to eq({ "/#{owner.username}/#{repo.id}" => "Laser Lamp" })
    end

    it "shows the like button as liked to a user who has liked the repository" do
      Like.create!(repository: repo, user: stranger)
      content_login!(stranger)
      get repo_path
      expect(Nokogiri::HTML(response.body).at_css("span.like.liked")).to be_present
    end

    describe "comments" do
      let(:commenter) { create(:user, :regular_user, reputation: 42) }

      before do
        create(:comment, repository: repo, user: commenter, content: "Older and popular", upvote: 9, created_at: 2.days.ago)
        create(:comment, repository: repo, user: commenter, content: "Newer and quiet", upvote: 1, created_at: 1.day.ago)
      end

      def listed_comments
        Nokogiri::HTML(response.body).css("#comment-container .comment-content").map { |c| c.text.strip }
      end

      it "lists the comments by votes by default, each with its author's reputation" do
        get repo_path
        expect(listed_comments).to eq(["Older and popular", "Newer and quiet"])
        expect(Nokogiri::HTML(response.body).css("#comment-container .rep").map { |r| r.text.strip }).to eq(%w[42 42])
      end

      it "lists the comments by votes for the top filter" do
        get repo_path, params: { comment_filter: "top" }
        expect(listed_comments).to eq(["Older and popular", "Newer and quiet"])
      end

      it "lists the newest comment first for the newest filter" do
        get repo_path, params: { comment_filter: "newest" }
        expect(listed_comments).to eq(["Newer and quiet", "Older and popular"])
      end
    end

    it "does not count as a view anywhere (no counters on the model)" do
      expect { get repo_path }.not_to change { repo.reload.attributes }
    end

    it "finds the repository by id, slug and title" do
      [repo.id, repo.slug, "Laser Lamp"].each do |key|
        get repository_path(repo.user_username, key)
        expect(response).to have_http_status(:ok)
      end
    end

    # a temporary (302) redirect, so browsers do not keep it across username changes
    it "sends a link with another username to the owner's address" do
      get repository_path("anybody-at-all", repo.slug), params: { page: "2" }
      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(repository_path(repo.user_username, repo.slug, page: "2"))
    end

    it "shows the member forms to owners and admin only, the link-to-proposal form to members and staff too" do
      forms = ->(path) { %w[link_to_pp add_member remove_member].select { |a| response.body.include?("/#{a}") } }
      content_login!(owner)
      get repo_path
      expect(forms.call(nil)).to eq(%w[link_to_pp add_member remove_member])
      content_sign_in_as(:admin)
      get repo_path
      expect(forms.call(nil)).to eq(%w[link_to_pp add_member remove_member])
      # staff cannot use the member forms (check_ownership), so they are no longer rendered
      content_sign_in_as(:staff)
      get repo_path
      expect(forms.call(nil)).to eq(%w[link_to_pp])
      member = create(:user, :regular_user)
      repo.users << member
      content_login!(member)
      get repo_path
      expect(forms.call(nil)).to eq(%w[link_to_pp])
      content_login!(stranger)
      get repo_path
      expect(forms.call(nil)).to be_empty
    end

    it "strips a format suffix from the id" do
      get repository_path(repo.user_username, "#{repo.id}.json") rescue nil
      expect(response.status).to be < 500
    end

    it "raises RecordNotFound for an unknown repository" do
      get repository_path(owner.username, "nope-nope")
      expect(response).to have_http_status(:not_found)
    end

    it "treats a soft-deleted repository as nonexistent (default_scope)" do
      repo.update_columns(deleted: true)
      get repo_path
      expect(response).to have_http_status(:not_found)
    end

    context "when private" do
      let!(:secret) do
        create(:repository, :private, owner: owner, title: "Secret", users: [owner])
      end

      it "redirects a guest to the password entry page" do
        get repo_path(secret)
        expect(response).to redirect_to(password_entry_repository_path(owner.username, secret.id))
        follow_redirect!
        # the guest lands on the password page, not /login
        expect(response).to have_http_status(:ok)
      end

      it "redirects a signed-in stranger to the password entry page" do
        content_login!(stranger)
        get repo_path(secret)
        expect(response).to redirect_to(password_entry_repository_path(owner.username, secret.id))
      end

      # the owner-username redirect only happens for people who pass the access check
      it "does not name the owner to a guest or stranger who holds the id with another username" do
        [nil, stranger].each do |viewer|
          content_login!(viewer) if viewer
          %i[repository_path password_entry_repository_path].each do |helper|
            get send(helper, "someone-else", secret.id)
            expect(response.headers["Location"].to_s).not_to include(owner.username), "#{helper} #{viewer.inspect}"
          end
          get download_files_repositories_path("someone-else", secret.id)
          expect(response.headers["Location"].to_s).not_to include(owner.username)
          expect(response.headers["Location"].to_s).to include("password_entry").or include("/login").or be_blank
        end
      end

      it "still sends the owner to the owner's address" do
        content_login!(owner)
        get repository_path("someone-else", secret.id)
        expect(response).to redirect_to(repository_path(owner.username, secret.id))
        expect(response).to have_http_status(:found)
      end

      it "lets the owner (by username), staff and admin straight in" do
        content_login!(owner)
        get repo_path(secret)
        expect(response).to have_http_status(:ok)
      end

      %i[staff admin].each do |role|
        it "lets #{role} straight in" do
          content_sign_in_as(role)
          get repo_path(secret)
          expect(response).to have_http_status(:ok)
        end
      end

      it "lets a collaborator (in users, not the owner) in without the password" do
        collaborator = create(:user, :regular_user)
        secret.users << collaborator
        content_login!(collaborator)
        get repo_path(secret)
        # members of repository.users are authorized like the owner
        expect(response).to have_http_status(:ok)
      end

      it "lets the owner in by user_id even when not in users" do
        secret.users.clear
        content_login!(owner)
        get repo_path(secret)
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "password entry as a guest" do
    let!(:secret) { create(:repository, :private, owner: owner, title: "Secret", users: [owner]) }

    before { secret.update_columns(password: BCrypt::Password.create("open-sesame")) }

    it "a guest can open the password page and enter the password" do
      get password_entry_repository_path(owner.username, secret.id)
      # password_entry / pass_authenticate do not require a login
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("This project is private")
      expect(response.body).not_to include("Secret")
      post pass_authenticate_repository_path(owner.username, secret.id), params: { password: "open-sesame" }
      expect(response).to redirect_to(repo_path(secret))
      get repo_path(secret)
      expect(response).to have_http_status(:ok)
    end

    it "a guest with a wrong password is bounced back and sees nothing" do
      post pass_authenticate_repository_path(owner.username, secret.id), params: { password: "nope" }
      expect(response).to redirect_to(password_entry_repository_path(owner.username, secret.id))
      get repo_path(secret)
      expect(response).to redirect_to(password_entry_repository_path(owner.username, secret.id))
    end

    it "the guest password page for a public repository redirects to show, and the other private actions still need a login" do
      get password_entry_repository_path(owner.username, repo.id)
      expect(response).to redirect_to(repository_path(owner.username, repo.id))
      post pass_authenticate_repository_path(owner.username, repo.id), params: { password: "x" }
      expect(response).to redirect_to(repo_path)
      post add_like_repository_path(owner.username, secret.slug)
      expect(response.location).to include("/login")
      get edit_repository_path(owner.username, repo.slug)
      expect(response.location).to include("/login")
    end
  end

  describe "password entry / authentication" do
    let!(:secret) do
      create(:repository, :private, owner: owner, title: "Secret", users: [owner])
    end

    # The :private trait stores a bcrypt hash; build a known one.
    before do
      secret.update_columns(password: BCrypt::Password.create("open-sesame"))
      content_login!(stranger)
    end

    it "GET password_entry renders for private repositories" do
      get password_entry_repository_path(owner.username, secret.id)
      expect(response).to have_http_status(:ok)
    end

    it "GET password_entry redirects public repositories to show (by id)" do
      get password_entry_repository_path(owner.username, repo.id)
      expect(response).to redirect_to(repository_path(owner.username, repo.id))
    end

    it "a correct password redirects to the slug URL, which is then accepted" do
      post pass_authenticate_repository_path(owner.username, secret.id), params: { password: "open-sesame" }
      expect(response).to redirect_to(repo_path(secret))
      expect(flash[:notice]).to eq("Success")
      follow_redirect!
      # the session stores the repository id, so the slug URL is recognised
      expect(response).to have_http_status(:ok)
    end

    it "the numeric-id URL is recognised after a correct password" do
      post pass_authenticate_repository_path(owner.username, secret.id), params: { password: "open-sesame" }
      get repository_path(owner.username, secret.id)
      expect(response).to have_http_status(:ok)
    end

    it "authorization is remembered per repository: id, slug and title all pass, other repositories stay locked" do
      other = create(:repository, :private, owner: owner, title: "Other Secret", users: [owner])
      post pass_authenticate_repository_path(owner.username, secret.id), params: { password: "open-sesame" }
      get repository_path(owner.username, secret.id)
      expect(response).to have_http_status(:ok)
      get repository_path(owner.username, secret.title)
      # whitelist is by repository id, normalised across id/slug/title
      expect(response).to have_http_status(:ok)
      get repo_path(secret)
      expect(response).to have_http_status(:ok)
      get repo_path(other)
      expect(response).to redirect_to(password_entry_repository_path(owner.username, other.id))
    end

    it "pass_authenticate posted to the slug URL also unlocks" do
      post pass_authenticate_repository_path(owner.username, secret.slug), params: { password: "open-sesame" }
      expect(flash[:notice]).to eq("Success")
      get repository_path(owner.username, secret.id)
      expect(response).to have_http_status(:ok)
    end

    it "a wrong password redirects back with an alert and grants nothing" do
      post pass_authenticate_repository_path(owner.username, secret.id), params: { password: "nope" }
      expect(response).to redirect_to(password_entry_repository_path(owner.username, secret.id))
      expect(flash[:alert]).to eq("Incorrect password. Try again!")
      get repo_path(secret)
      expect(response).to redirect_to(password_entry_repository_path(owner.username, secret.id))
    end

    # test env uses :null_store (never counts), so back the limiter's store with a counter
    context "rate limit" do
      let(:counts) { Hash.new(0) }

      before do
        allow(RateLimitCounter).to receive(:increment) { |key, *| counts[key] += 1 }
      end

      def guess(r = secret, password: "wrong")
        post pass_authenticate_repository_path(owner.username, r.id), params: { password: password }
      end

      it "allows 10 guesses, then refuses even the correct password" do
        10.times do
          guess
          expect(flash[:alert]).to eq("Incorrect password. Try again!")
        end
        guess(password: "open-sesame")
        # pass_authenticate is rate limited (10 per 10 minutes) per repository and user/IP
        expect(response).to redirect_to(password_entry_repository_path(owner.username, secret.id))
        expect(flash[:alert]).to eq("Too many attempts. Please try again later.")
        get repo_path(secret)
        expect(response).to redirect_to(password_entry_repository_path(owner.username, secret.id))
      end

      it "counts per repository (id, slug and title share one bucket) and per user" do
        other = create(:repository, :private, owner: owner, title: "Other Secret", users: [owner])
        other.update_columns(password: BCrypt::Password.create("open-sesame"))
        5.times { guess }
        post pass_authenticate_repository_path(owner.username, secret.slug), params: { password: "x" }
        post pass_authenticate_repository_path(owner.username, secret.title), params: { password: "x" }
        3.times { guess }
        guess
        expect(flash[:alert]).to eq("Too many attempts. Please try again later.")
        guess(other, password: "open-sesame")
        expect(flash[:notice]).to eq("Success")
        content_login!(create(:user, :regular_user))
        guess(password: "open-sesame")
        expect(flash[:notice]).to eq("Success")
      end

      it "throttles a guest by IP" do
        reset!
        10.times { guess }
        guess(password: "open-sesame")
        expect(flash[:alert]).to eq("Too many attempts. Please try again later.")
      end
    end

    it "pass_authenticate on a public repository redirects to show instead of raising" do
      post pass_authenticate_repository_path(owner.username, repo.id), params: { password: "x" }
      # a public repository has no password to check; go to show
      expect(response).to redirect_to(repo_path)
    end
  end

  describe "GET new / POST create" do
    it "redirects a guest to login for new and create" do
      get new_repository_path(owner.username)
      expect(response).to redirect_to(login_path(back_to: "/#{owner.username}/new"))
      expect { post repositories_path(owner.username), params: valid_params }.not_to change(Repository, :count)
      expect(response).to have_http_status(:found)
    end

    it "renders the new form for a signed-in user" do
      content_login!(stranger)
      get new_repository_path(stranger.username)
      expect(response).to have_http_status(:ok)
    end

    it "renders the new form for a given project proposal with the proposal fixed and no proposal list" do
      proposal = create(:project_proposal, :approved)
      content_login!(stranger)
      get new_repository_path(stranger.username, project_proposal_id: proposal.id)
      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("input[type='hidden'][name='repository[project_proposal_id]']")["value"]).to eq(proposal.id.to_s)
      expect(page.at_css("select[name='repository[project_proposal_id]']")).to be_nil
    end

    it "creates a repository owned by the current user (ignores the URL username), +25 reputation" do
      content_login!(stranger)
      expect do
        post repositories_path(owner.username), params: valid_params(title: "Mine Now")
      end.to change(Repository, :count).by(1)
      made = Repository.find_by(title: "Mine Now")
      expect(made.user_id).to eq(stranger.id)
      expect(made.users).to eq([stranger])
      expect(made.photos.count).to eq(1)
      expect(made.slug).to eq("#{made.id}.mine-now") # photo nested save touches the repo, firing before_update
      expect(stranger.reload.reputation).to eq(25)
      expect(response).to redirect_to("/#{stranger.username}/#{made.slug}")
    end

    it "ignores a user_id param (strong params permit it, but create overwrites it)" do
      content_login!(stranger)
      post repositories_path(owner.username), params: valid_params(title: "Spoof", user_id: owner.id)
      expect(Repository.find_by(title: "Spoof").user_id).to eq(stranger.id)
    end

    it "stores a new repository's slug as '<id>.<title>'" do
      content_login!(stranger)
      post repositories_path(stranger.username), params: valid_params(title: "Zed Title")
      made = Repository.find_by(title: "Zed Title")
      expect(made.slug).to eq("#{made.id}.zed-title")
    end

    it "adds the creator once when params[:owner] names the creator too" do
      content_login!(stranger)
      post repositories_path(owner.username), params: valid_params(title: "Solo").merge(owner: [stranger.id])
      expect(Repository.find_by(title: "Solo").users.to_a).to eq([stranger])
    end

    it "awards no reputation for a refused create" do
      content_login!(stranger)
      post repositories_path(stranger.username), params: valid_params(title: "")
      expect(response).to have_http_status(:unprocessable_content)
      expect(stranger.reload.reputation).to eq(0)
    end

    it "adds extra owners from params[:owner] when they exist (silently skips unknown ids)" do
      content_login!(stranger)
      post repositories_path(owner.username),
           params: valid_params(title: "Team").merge(owner: [owner.id, 0])
      expect(Repository.find_by(title: "Team").users).to contain_exactly(stranger, owner)
    end

    it "creates categories and equipment (max 5 each) and EquipmentOption rows" do
      content_login!(stranger)
      post repositories_path(owner.username),
           params: valid_params(title: "Tagged",
                                categories: %w[A B C D E F ""].map { |c| c == '""' ? "" : c },
                                equipments: %w[Laser Printer])
      made = Repository.find_by(title: "Tagged")
      expect(made.categories.pluck(:name)).to match_array(%w[A B C D E])
      expect(made.equipments.pluck(:name)).to match_array(%w[Laser Printer])
      expect(EquipmentOption.where(name: %w[Laser Printer]).count).to eq(2)
    end

    it "a private repository without a password re-renders new with 422" do
      content_login!(stranger)
      expect do
        post repositories_path(owner.username), params: valid_params(title: "Hidden", share_type: "private")
      end.not_to change(Repository, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "stores a private repository password as the bcrypt of the joined password array" do
      content_login!(stranger)
      post repositories_path(owner.username),
           params: valid_params(title: "Hidden", share_type: "private").merge(password: %w[ab cd])
      made = Repository.find_by(title: "Hidden")
      expect(BCrypt::Password.new(made.password)).to eq("abcd")
      expect(made.private?).to be(true)
    end

    it "rejects a missing title, a duplicate title for the same owner, and zero photos with 422" do
      content_login!(stranger)
      create(:repository, owner: stranger, title: "Dup", users: [stranger])
      [valid_params(title: ""), valid_params(title: "Dup")].each do |p|
        expect { post repositories_path(stranger.username), params: p }.not_to change(Repository, :count)
        expect(response).to have_http_status(:unprocessable_content)
      end
      expect do
        post repositories_path(stranger.username), params: { repository: { title: "NoPic", share_type: "public" } }
      end.not_to change(Repository, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects a gallery photo over the size limit with 422" do
      content_login!(stranger)
      p = valid_params(title: "BigPic")
      p[:repository][:photos_attributes] = { "0" => { image: content_png_upload_of_size(Photo::MAX_IMAGE_SIZE + 1) } }
      expect { post repositories_path(stranger.username), params: p }.not_to change(Repository, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "accepts a gallery photo exactly at the size limit" do
      content_login!(stranger)
      p = valid_params(title: "LimitPic")
      p[:repository][:photos_attributes] = { "0" => { image: content_png_upload_of_size(Photo::MAX_IMAGE_SIZE) } }
      expect { post repositories_path(stranger.username), params: p }.to change(Repository, :count).by(1)
    end

    it "rejects a non-image gallery upload (content-type validation) with 422" do
      content_login!(stranger)
      p = valid_params(title: "BadPic")
      p[:repository][:photos_attributes] = { "0" => { image: content_stl_upload } }
      expect { post repositories_path(stranger.username), params: p }.not_to change(Repository, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    # RepoFile validates the sniffed content type and size for every repository file
    it "refuses an executable as a repo_file on a repository, even with a friendly name or declared type" do
      content_login!(stranger)
      exe = "MZ" + ("\x00" * 200)
      [["evil.exe", "application/x-msdownload"], ["design.stl", "model/stl"], ["notes.txt", "text/plain"]].each do |name, type|
        p = valid_params(title: "Files #{name}")
        p[:repository][:repo_files_attributes] = { "0" => { file: content_named_upload(name, content: exe, type: type) } }
        expect { post repositories_path(stranger.username), params: p }.not_to change(RepoFile, :count)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    it "refuses html and shell scripts as repo_files" do
      content_login!(stranger)
      { "page.stl" => "<!DOCTYPE html><html><script>alert(1)</script></html>", "run.sh" => "#!/bin/sh\nrm -rf /\n" }.each do |name, body|
        p = valid_params(title: "Bad #{name}")
        p[:repository][:repo_files_attributes] = { "0" => { file: content_named_upload(name, content: body, type: "text/plain") } }
        expect { post repositories_path(stranger.username), params: p }.not_to change(RepoFile, :count)
      end
    end

    it "still accepts the legitimate project file types (pdf, stl, zip, text, gcode, step, docx)" do
      content_login!(stranger)
      files = {
        "a.pdf" => ["%PDF-1.4\n", "application/pdf"],
        "a.stl" => ["solid x\nfacet normal 0 0 0\n", "model/stl"],
        "a.zip" => ["PK\x03\x04".b + ("\x00" * 40), "application/zip"],
        "a.txt" => ["hello", "text/plain"],
        "a.gcode" => ["G28\nG1 X0\n", "application/octet-stream"],
        "a.step" => ["ISO-10303-21;\nHEADER;", "application/octet-stream"],
        "a.docx" => ["PK\x03\x04".b + ("\x00" * 40), "application/octet-stream"]
      }
      files.each do |name, (body, type)|
        p = valid_params(title: "Ok #{name}")
        p[:repository][:repo_files_attributes] = { "0" => { file: content_named_upload(name, content: body, type: type) } }
        expect { post repositories_path(stranger.username), params: p }.to change(RepoFile, :count).by(1), name
      end
    end

    it "refuses a repo_file over the size cap" do
      stub_const("RepoFile::MAX_FILE_SIZE", 10.bytes)
      content_login!(stranger)
      p = valid_params(title: "Huge")
      p[:repository][:repo_files_attributes] = { "0" => { file: content_named_upload("big.txt", content: "x" * 11) } }
      expect { post repositories_path(stranger.username), params: p }.not_to change(RepoFile, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "an unparseable youtube link is silently nulled" do
      content_login!(stranger)
      post repositories_path(stranger.username), params: valid_params(title: "Yt", youtube_link: "https://google.ca")
      expect(Repository.find_by(title: "Yt").youtube_link).to be_nil
    end

    # Owners, categories and equipment have no validations of their own, so these steps fail only by raising.
    # The error is answered by the error page (422 for these errors) after the whole create has rolled back.
    context "when a step after the save fails" do
      before { content_login!(stranger) }

      def fail_owner_join_for(user)
        allow_any_instance_of(Repository.const_get(:HABTM_Users)).to receive(:create_or_update).and_wrap_original do |m, *args, **opts, &blk|
          raise ActiveRecord::RecordNotSaved, "join refused" if m.receiver.user_id == user.id

          m.call(*args, **opts, &blk)
        end
      end

      def expect_nothing_stored(params)
        counts = -> { [Repository.count, Photo.count, Category.count, Equipment.count, EquipmentOption.count] }
        expect { post repositories_path(stranger.username), params: params }.not_to change(&counts)
        expect(response).to have_http_status(:unprocessable_content)
        expect(stranger.reload.reputation).to eq(0)
      end

      it "stores nothing and awards no reputation when an owner cannot be added" do
        fail_owner_join_for(owner)
        expect_nothing_stored(valid_params(title: "Partial").merge(owner: [owner.id]))
      end

      it "stores nothing and awards no reputation when a category cannot be stored" do
        allow_any_instance_of(Category).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)
        expect_nothing_stored(valid_params(title: "Partial", categories: %w[A]))
      end

      it "stores nothing and awards no reputation when equipment cannot be stored" do
        allow(Equipment).to receive(:create).and_raise(ActiveRecord::RecordNotSaved, "equipment refused")
        expect_nothing_stored(valid_params(title: "Partial", categories: %w[A], equipments: %w[Laser]))
      end

      it "creates the repository once when the same form is sent again after a failure" do
        allow(Equipment).to receive(:create).and_raise(ActiveRecord::RecordNotSaved, "equipment refused")
        post repositories_path(stranger.username), params: valid_params(title: "Retry", equipments: %w[Laser])
        allow(Equipment).to receive(:create).and_call_original
        expect { post repositories_path(stranger.username), params: valid_params(title: "Retry", equipments: %w[Laser]) }
          .to change(Repository, :count).by(1)
        expect(Repository.find_by(title: "Retry").equipments.pluck(:name)).to eq(["Laser"])
        expect(stranger.reload.reputation).to eq(25)
      end
    end

    it "responds with a redirect for missing repository params (parameter_missing -> root with alert)" do
      content_login!(stranger)
      post repositories_path(stranger.username), params: {}
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to include("repository")
    end
  end

  describe "GET edit" do
    it "sends a guest to login" do
      get edit_repository_path(owner.username, repo.slug)
      expect(response).to redirect_to(login_path(back_to: "/#{owner.username}/#{repo.slug}/edit"))
    end

    it "bounces a stranger back to the repository with an alert" do
      content_login!(stranger)
      get edit_repository_path(owner.username, repo.slug)
      expect(response).to redirect_to(repo_path)
      expect(flash[:alert]).to eq("You are not allowed to perform this action!")
    end

    it "renders for a member, and for admin" do
      content_login!(owner)
      get edit_repository_path(owner.username, repo.slug)
      expect(response).to have_http_status(:ok)
    end

    it "renders for admin" do
      content_sign_in_as(:admin)
      get edit_repository_path(owner.username, repo.slug)
      expect(response).to have_http_status(:ok)
    end

    it "styles the categories and equipment selects as multiple-choice form selects" do
      content_login!(owner)
      get edit_repository_path(owner.username, repo.slug)
      %w[categories equipments].each do |field|
        select = Nokogiri::HTML(response.body).at_css("select[name='repository[#{field}][]']")
        expect(select["class"].to_s.split).to include("form-control", "form-select")
        expect(select["multiple"]).to be_present
      end
    end

    it "always sends the category field, so clearing every category is submitted" do
      content_login!(owner)
      get edit_repository_path(owner.username, repo.slug)
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("input[type='hidden'][name='repository[categories][]'][value='']")).to be_present
    end

    it "renders the edit form for a given project proposal with the proposal fixed and no proposal list" do
      proposal = create(:project_proposal, :approved)
      content_login!(owner)
      get edit_repository_path(owner.username, repo.slug, project_proposal_id: proposal.id)
      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("input[type='hidden'][name='repository[project_proposal_id]']")["value"]).to eq(proposal.id.to_s)
      expect(page.at_css("select[name='repository[project_proposal_id]']")).to be_nil
    end

    it "always sends the equipment field, so clearing all equipment is submitted" do
      content_login!(owner)
      get edit_repository_path(owner.username, repo.slug)
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("input[type='hidden'][name='repository[equipments][]'][value='']")).to be_present
    end

    it "bounces staff (staff can view private repos but not edit)" do
      content_sign_in_as(:staff)
      get edit_repository_path(owner.username, repo.slug)
      expect(response).to redirect_to(repo_path)
    end

    it "lets the repository owner edit when the owner is not in repository.users" do
      orphan = create(:repository, owner: owner, title: "Orphan") # factory: users empty
      content_login!(owner)
      get edit_repository_path(owner.username, orphan.slug)
      # owner is user_id OR a member of the habtm `users`
      expect(response).to have_http_status(:ok)
    end

    it "lets a collaborator (in users, not the owner) edit, and still bounces a stranger from an orphan repo" do
      collaborator = create(:user, :regular_user)
      repo.users << collaborator
      content_login!(collaborator)
      get edit_repository_path(owner.username, repo.slug)
      expect(response).to have_http_status(:ok)

      orphan = create(:repository, owner: owner, title: "Orphan")
      content_login!(stranger)
      get edit_repository_path(owner.username, orphan.slug)
      expect(response).to redirect_to(repository_path(owner.username, orphan.slug))
      expect(flash[:alert]).to eq("You are not allowed to perform this action!")
    end
  end

  describe "PATCH update" do
    let(:update_params) { { repository: { title: "Renamed", description: "new", share_type: "public" } } }

    it "sends a guest to login and changes nothing" do
      patch repository_path(owner.username, repo.slug), params: update_params
      expect(response).to have_http_status(:found)
      expect(repo.reload.title).to eq("Laser Lamp")
    end

    it "refuses a stranger and changes nothing" do
      content_login!(stranger)
      patch repository_path(owner.username, repo.slug), params: update_params
      expect(response).to redirect_to(repo_path)
      expect(flash[:alert]).to eq("You are not allowed to perform this action!")
      expect(repo.reload.title).to eq("Laser Lamp")
    end

    it "lets a member update; the slug becomes '<id>.<title-slug>' and the flash is set" do
      content_login!(owner)
      patch repository_path(owner.username, repo.slug), params: update_params
      expect(repo.reload.title).to eq("Renamed")
      expect(repo.slug).to eq("#{repo.id}.renamed")
      expect(flash[:notice]).to eq("Project updated successfully!")
      expect(response).to redirect_to("/#{owner.username}/#{repo.slug}")
    end

    it "lets admin update" do
      content_sign_in_as(:admin)
      patch repository_path(owner.username, repo.slug), params: update_params
      expect(repo.reload.title).to eq("Renamed")
    end

    it "lets a collaborator update" do
      collab = create(:user, :regular_user)
      repo.users << collab
      content_login!(collab)
      patch repository_path(owner.username, repo.slug), params: update_params
      expect(repo.reload.title).to eq("Renamed")
    end

    it "drops the cached zip of the updated repository" do
      cache_dir = Pathname(Dir.mktmpdir("repository_zips"))
      allow(Repository::ZipCache).to receive(:directory).and_return(cache_dir)
      FileUtils.touch(repo.zip_path)
      content_login!(owner)
      patch repository_path(owner.username, repo.slug), params: update_params
      expect(File.exist?(repo.zip_path)).to be(false)
    ensure
      FileUtils.rm_rf(cache_dir.to_s)
    end

    it "replaces categories and equipment wholesale (destroy_all then recreate)" do
      Category.create!(name: "Old", repository_id: repo.id)
      content_login!(owner)
      patch repository_path(owner.username, repo.slug),
            params: update_params.deep_merge(repository: { categories: %w[New], equipments: [] })
      expect(repo.reload.categories.pluck(:name)).to eq(["New"])
      expect(repo.equipments).to be_empty
    end

    it "keeps categories and equipment when the update is refused" do
      Category.create!(name: "Old", repository_id: repo.id)
      Equipment.create!(name: "Laser Cutter", repository_id: repo.id)
      content_login!(owner)
      patch repository_path(owner.username, repo.slug),
            params: { repository: { title: "", categories: %w[New], equipments: %w[Printer] } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to eq("The project was not updated. Title Project title is required.")
      expect(repo.reload.categories.pluck(:name)).to eq(["Old"])
      expect(repo.equipments.pluck(:name)).to eq(["Laser Cutter"])
      expect(repo.title).to eq("Laser Lamp")
    end

    it "keeps categories and equipment when the update is refused with none submitted" do
      Category.create!(name: "Old", repository_id: repo.id)
      content_login!(owner)
      patch repository_path(owner.username, repo.slug), params: { repository: { title: "" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to eq("The project was not updated. Title Project title is required.")
      expect(repo.reload.categories.pluck(:name)).to eq(["Old"])
    end

    it "sets categories and equipment as submitted on a valid update" do
      Category.create!(name: "Old", repository_id: repo.id)
      Equipment.create!(name: "Laser Cutter", repository_id: repo.id)
      content_login!(owner)
      patch repository_path(owner.username, repo.slug),
            params: update_params.deep_merge(repository: { categories: %w[New Newer], equipments: %w[Printer] })
      expect(response).to redirect_to("/#{owner.username}/#{repo.reload.slug}")
      expect(repo.categories.pluck(:name)).to match_array(%w[New Newer])
      expect(repo.equipments.pluck(:name)).to eq(["Printer"])
    end

    it "clears the categories when the form sends an empty selection" do
      Category.create!(name: "Old", repository_id: repo.id)
      content_login!(owner)
      patch repository_path(owner.username, repo.slug), params: update_params.deep_merge(repository: { categories: [""] })
      expect(repo.reload.categories).to be_empty
    end

    it "keeps the categories when a valid update does not send the field" do
      Category.create!(name: "Old", repository_id: repo.id)
      content_login!(owner)
      patch repository_path(owner.username, repo.slug), params: update_params
      expect(repo.reload.title).to eq("Renamed")
      expect(repo.categories.pluck(:name)).to eq(["Old"])
    end

    it "clears the equipment when the form sends an empty selection" do
      Equipment.create!(name: "Laser Cutter", repository_id: repo.id)
      content_login!(owner)
      patch repository_path(owner.username, repo.slug), params: update_params.deep_merge(repository: { equipments: [""] })
      expect(repo.reload.title).to eq("Renamed")
      expect(repo.equipments).to be_empty
    end

    it "keeps the equipment when a valid update does not send the field" do
      Equipment.create!(name: "Laser Cutter", repository_id: repo.id)
      content_login!(owner)
      patch repository_path(owner.username, repo.slug), params: update_params
      expect(repo.reload.title).to eq("Renamed")
      expect(repo.equipments.pluck(:name)).to eq(["Laser Cutter"])
    end

    it "keeps the equipment when a JSON update does not send the field" do
      Equipment.create!(name: "Laser Cutter", repository_id: repo.id)
      content_login!(owner)
      patch repository_path(owner.username, repo.slug), params: update_params, as: :json
      expect(repo.reload.title).to eq("Renamed")
      expect(repo.equipments.pluck(:name)).to eq(["Laser Cutter"])
    end

    it "replaces the equipment when a JSON update sends the field, and clears it when the list is empty" do
      Equipment.create!(name: "Laser Cutter", repository_id: repo.id)
      content_login!(owner)
      patch repository_path(owner.username, repo.slug), params: update_params.deep_merge(repository: { equipments: %w[Printer] }), as: :json
      expect(repo.reload.equipments.pluck(:name)).to eq(["Printer"])
      patch repository_path(owner.username, repo.slug), params: update_params.deep_merge(repository: { equipments: [] }), as: :json
      expect(repo.reload.equipments).to be_empty
    end

    it "keeps the equipment when a scalar value is sent instead of a list" do
      Equipment.create!(name: "Laser Cutter", repository_id: repo.id)
      content_login!(owner)
      patch repository_path(owner.username, repo.slug), params: update_params.deep_merge(repository: { equipments: "Printer" })
      expect(repo.reload.title).to eq("Renamed")
      expect(repo.equipments.pluck(:name)).to eq(["Laser Cutter"])
    end

    it "shows a refused edit for a given project proposal again with the proposal fixed" do
      proposal = create(:project_proposal, :approved)
      content_login!(owner)
      patch repository_path(owner.username, repo.slug), params: { project_proposal_id: proposal.id, repository: { title: "" } }
      expect(response).to have_http_status(:unprocessable_content)
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("input[type='hidden'][name='repository[project_proposal_id]']")["value"]).to eq(proposal.id.to_s)
      expect(repo.reload.title).to eq("Laser Lamp")
    end

    it "keeps the stored password when a refused update sends a new one" do
      secret = create(:repository, :private, owner: owner, title: "Sec", users: [owner])
      stored = secret.password
      content_login!(owner)
      patch repository_path(owner.username, secret.slug), params: { password: ["changed"], repository: { title: "", share_type: "private" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(secret.reload.password).to eq(stored)
    end

    it "keeps categories and equipment for a stranger's refused update" do
      Category.create!(name: "Old", repository_id: repo.id)
      content_login!(stranger)
      patch repository_path(owner.username, repo.slug), params: update_params.deep_merge(repository: { categories: %w[New] })
      expect(repo.reload.categories.pluck(:name)).to eq(["Old"])
    end

    it "switching to public clears the password" do
      secret = create(:repository, :private, owner: owner, title: "Sec", users: [owner])
      content_login!(owner)
      patch repository_path(owner.username, secret.slug), params: { repository: { share_type: "public" } }
      expect(secret.reload.share_type).to eq("public")
      expect(secret.password).to be_nil
    end

    it "a member cannot reassign user_id (ownership) via mass assignment" do
      collab = create(:user, :regular_user)
      repo.users << collab
      content_login!(collab)
      patch repository_path(owner.username, repo.slug), params: { repository: { user_id: collab.id } }
      # :user_id removed from repository_params; transfer_owner is the only way
      expect(repo.reload.user_id).to eq(owner.id)
    end

    it "can add and soft-remove a photo through nested attributes" do
      content_login!(owner)
      photo = repo.photos.first
      patch repository_path(owner.username, repo.slug),
            params: { repository: { photos_attributes: { "0" => { image: content_png_upload }, "1" => { id: photo.id, _destroy: "1" } } } }
      expect(repo.reload.photos.count).to eq(1)
      expect(Photo.exists?(photo.id)).to be(false)
    end

    it "refuses a new photo over the size limit and keeps the stored one" do
      content_login!(owner)
      photo = repo.photos.first
      big = content_png_upload_of_size(Photo::MAX_IMAGE_SIZE + 1)
      patch repository_path(owner.username, repo.slug),
            params: { repository: { photos_attributes: { "0" => { image: big }, "1" => { id: photo.id, _destroy: "1" } } } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("larger than 10 MB")
      expect(Photo.exists?(photo.id)).to be(true)
      expect(repo.reload.photos.count).to eq(1)
    end

    it "still saves an edit of a repository whose stored photo is over the size limit" do
      content_login!(owner)
      repo.photos.first.image.blob.update_column(:byte_size, Photo::MAX_IMAGE_SIZE * 3)
      patch repository_path(owner.username, repo.slug), params: { repository: { description: "edited" } }
      expect(response).not_to have_http_status(:unprocessable_content)
      expect(repo.reload.description).to include("edited")
    end

    it "removing every photo fails validation (1..10 photos)" do
      content_login!(owner)
      photo = repo.photos.first
      patch repository_path(owner.username, repo.slug),
            params: { repository: { photos_attributes: { "0" => { id: photo.id, _destroy: "1" } } } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE destroy" do
    it "sends a guest to login and keeps the repository" do
      expect { delete repository_path(owner.username, repo.slug) }.not_to change(Repository.unscoped, :count)
    end

    it "refuses a stranger" do
      content_login!(stranger)
      expect { delete repository_path(owner.username, repo.slug) }.not_to change(Repository, :count)
      expect(flash[:alert]).to eq("You are not allowed to perform this action!")
    end

    it "hides the repository for a member and takes 25 reputation back from each member" do
      owner.update!(reputation: 100)
      content_login!(owner)
      expect { delete repository_path(owner.username, repo.slug) }
        .to change(Repository, :count).by(-1).and not_change(Repository.unscoped, :count)
      expect(Repository.unscoped.find(repo.id)).to have_attributes(deleted: true, hidden_reason: "user_deleted")
      expect(response).to redirect_to(user_path(owner.username))
      expect(flash[:notice]).to eq("Repository has been successfully deleted.")
      expect(owner.reload.reputation).to eq(75)
    end

    it "refuses a member who is not the owner and keeps the repository" do
      member = create(:user, :regular_user)
      repo.users << member
      content_login!(member)
      expect { delete repository_path(owner.username, repo.slug) }.not_to change(Repository, :count)
      expect(flash[:alert]).to eq("You are not allowed to perform this action!")
      expect(response).to redirect_to(repo_path)
    end

    it "drops the cached zip of the deleted repository" do
      cache_dir = Pathname(Dir.mktmpdir("repository_zips"))
      allow(Repository::ZipCache).to receive(:directory).and_return(cache_dir)
      FileUtils.touch(repo.zip_path)
      content_login!(owner)
      delete repository_path(owner.username, repo.slug)
      expect(File.exist?(repo.zip_path)).to be(false)
    ensure
      FileUtils.rm_rf(cache_dir.to_s)
    end

    it "keeps photos, files, comments, likes, makes and stored files" do
      create(:comment, repository: repo, user: stranger)
      create(:like, repository: repo, user: stranger)
      make = create(:repository, owner: stranger, title: "Made from it", make_id: repo.id)
      blob_ids = ActiveStorage::Blob.pluck(:id)
      content_sign_in_as(:admin)
      expect { delete repository_path(owner.username, repo.slug) }
        .to not_change(Comment, :count).and not_change(Like, :count).and not_change(Photo, :count)
        .and not_change(ActiveStorage::Attachment, :count)
      expect(ActiveStorage::Blob.pluck(:id)).to match_array(blob_ids)
      expect(make.reload.make_id).to eq(repo.id)
      expect(make.parent).to eq(repo)
    end

    it "records an admin's deletion as deleted by an admin" do
      content_sign_in_as(:admin)
      delete repository_path(owner.username, repo.slug)
      expect(Repository.unscoped.find(repo.id)).to have_attributes(deleted: true, hidden_reason: "admin_deleted")
    end

    it "answers 404 for the hidden repository's page afterwards" do
      content_login!(owner)
      delete repository_path(owner.username, repo.slug)
      get repository_path(owner.username, repo.id)
      expect(response).to have_http_status(:not_found)
    end

    it "does not take the reputation back twice when the repository is deleted again" do
      owner.update!(reputation: 100)
      content_login!(owner)
      delete repository_path(owner.username, repo.slug)
      delete repository_path(owner.username, repo.slug)
      expect(response).to have_http_status(:not_found)
      expect(owner.reload.reputation).to eq(75)
    end

    it "lets the owner delete a repository whose users list does not include them" do
      orphan = create(:repository, owner: owner, title: "Orphan")
      content_login!(owner)
      expect { delete repository_path(owner.username, orphan.slug) }.to change(Repository, :count).by(-1)
      expect(Repository.unscoped.find(orphan.id).deleted).to be(true)
      content_login!(stranger)
      other = create(:repository, owner: owner, title: "Orphan Two")
      expect { delete repository_path(owner.username, other.slug) }.not_to change(Repository, :count)
    end

    it "answers 204 for a JSON delete" do
      content_login!(owner)
      delete repository_path(owner.username, repo.slug, format: :json)
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "POST add_like" do
    it "sends a guest to login" do
      expect { post add_like_repository_path(owner.username, repo.slug) }.not_to change(Like, :count)
      expect(response).to have_http_status(:found)
    end

    it "likes then unlikes, moving every member's reputation by 5 and the counter by 1" do
      content_login!(stranger)
      post add_like_repository_path(owner.username, repo.slug)
      expect(flash[:notice]).to eq("You have liked this project!")
      expect(repo.reload.like).to eq(1)
      expect(owner.reload.reputation).to eq(5)
      post add_like_repository_path(owner.username, repo.slug)
      expect(flash[:notice]).to eq("You have unliked this project")
      expect(repo.reload.like).to eq(0)
      expect(owner.reload.reputation).to eq(0)
    end

    it "counts a like once when the same user's like lands between the check and the insert" do
      content_login!(stranger)
      post add_like_repository_path(owner.username, repo.slug)
      allow_any_instance_of(Repository).to receive(:likes).and_wrap_original do |original|
        relation = original.call
        allow(relation).to receive(:find_by).and_return(nil)
        relation
      end

      expect { post add_like_repository_path(owner.username, repo.slug) }.not_to change(Like, :count)

      expect(response).to redirect_to(repository_path(owner.username, repo.slug))
      expect(repo.reload.like).to eq(1)
      expect(owner.reload.reputation).to eq(5)
    end

    it "reverses nothing when a simultaneous request already took the like back" do
      content_login!(stranger)
      post add_like_repository_path(owner.username, repo.slug)
      allow(Like).to receive(:take_back).and_return(false)

      expect { post add_like_repository_path(owner.username, repo.slug) }.not_to change { owner.reload.reputation }

      expect(response).to redirect_to(repository_path(owner.username, repo.slug))
    end

    it "refuses a like by the owner or a member of the repository" do
      member = create(:user, :regular_user)
      repo.users << member
      [owner, member].each do |user|
        content_login!(user)
        expect { post add_like_repository_path(owner.username, repo.slug) }.not_to change(Like, :count)
        expect(flash[:alert]).to eq("You cannot like a project you are a member of")
      end
      expect(repo.reload.like).to eq(0)
      expect(owner.reload.reputation).to eq(0)
    end

    it "lets a member take back a like given before" do
      Like.create!(repository: repo, user: owner)
      repo.update_column(:like, 1)
      content_login!(owner)
      expect { post add_like_repository_path(owner.username, repo.slug) }.to change(Like, :count).by(-1)
    end

    it "refuses to like a private repository without its password" do
      secret = create(:repository, :private, owner: owner, title: "Sec", users: [owner])
      content_login!(stranger)
      expect { post add_like_repository_path(owner.username, secret.slug) }.not_to change(Like, :count)
      # add_like runs the shared private-repository gate
      expect(response).to redirect_to(password_entry_repository_path(owner.username, secret.id))
    end

    it "lets a user who entered the password like a private repository, and refuses its owner and a collaborator" do
      secret = create(:repository, :private, owner: owner, title: "Sec", users: [owner])
      secret.update_columns(password: BCrypt::Password.create("open-sesame"))
      collaborator = create(:user, :regular_user)
      secret.users << collaborator
      [owner, collaborator].each do |u|
        content_login!(u)
        post add_like_repository_path(owner.username, secret.slug)
        expect(response).to redirect_to(repo_path(secret))
      end
      expect(Like.where(repository_id: secret.id)).to be_empty
      content_login!(stranger)
      post pass_authenticate_repository_path(owner.username, secret.id), params: { password: "open-sesame" }
      expect { post add_like_repository_path(owner.username, secret.slug) }.to change(Like, :count).by(1)
    end
  end

  describe "member management (link_to_pp / add_member / remove_member / transfer_owner)" do
    let(:newbie) { create(:user, :regular_user) }

    it "all require sign in" do
      patch add_member_repositories_path(owner.username),
            params: { repo_owner: { repository_id: repo.id, owner_username: newbie.username } }
      expect(response).to have_http_status(:found)
      expect(response.location).to include("/login")
      expect(repo.reload.users).to eq([owner])
    end

    it "refuses a signed-in stranger adding a member to someone else's repository" do
      content_login!(stranger)
      patch add_member_repositories_path(owner.username),
            params: { repo_owner: { repository_id: repo.id, owner_username: newbie.username } }
      # add_member runs check_ownership (owner or admin)
      expect(repo.reload.users).to eq([owner])
      expect(flash[:alert]).to eq("You are not allowed to perform this action!")
      expect(response).to redirect_to(repo_path)
    end

    it "lets the owner (even when not in users) and admin add a member" do
      orphan = create(:repository, owner: owner, title: "Orphan")
      content_login!(owner)
      patch add_member_repositories_path(owner.username),
            params: { repo_owner: { repository_id: orphan.id, owner_username: newbie.username } }
      expect(orphan.reload.users).to eq([newbie])
      expect(flash[:notice]).to eq("This user was added to your repository.")

      third = create(:user, :regular_user)
      content_sign_in_as(:admin)
      patch add_member_repositories_path(owner.username),
            params: { repo_owner: { repository_id: orphan.id, owner_username: third.username } }
      expect(orphan.reload.users).to contain_exactly(newbie, third)
    end

    it "refuses a member who is not the owner adding or removing members" do
      repo.users << newbie
      content_login!(newbie)
      patch add_member_repositories_path(owner.username),
            params: { repo_owner: { repository_id: repo.id, owner_username: stranger.username } }
      expect(flash[:alert]).to eq("You are not allowed to perform this action!")
      expect(response).to redirect_to(repo_path)
      patch remove_member_repositories_path(owner.username),
            params: { repo_owner: { repository_id: repo.id, owner_id: owner.id } }
      expect(flash[:alert]).to eq("You are not allowed to perform this action!")
      expect(repo.reload.users).to contain_exactly(owner, newbie)
    end

    it "refuses staff adding a member (staff are not repository owners)" do
      content_sign_in_as(:staff)
      patch add_member_repositories_path(owner.username),
            params: { repo_owner: { repository_id: repo.id, owner_username: newbie.username } }
      expect(repo.reload.users).to eq([owner])
    end

    it "add_member reports unknown users and duplicates" do
      content_login!(owner)
      patch add_member_repositories_path(owner.username),
            params: { repo_owner: { repository_id: repo.id, owner_username: "ghost" } }
      expect(flash[:alert]).to eq("Couldn't find user, please try again.")
      patch add_member_repositories_path(owner.username),
            params: { repo_owner: { repository_id: repo.id, owner_username: owner.username } }
      expect(flash[:alert]).to eq("This user is already a member of your repository.")
    end

    it "refuses a signed-in stranger removing a member from someone else's repository" do
      repo.users << newbie
      content_login!(stranger)
      patch remove_member_repositories_path(owner.username),
            params: { repo_owner: { repository_id: repo.id, owner_id: newbie.id } }
      # remove_member runs check_ownership
      expect(repo.reload.users).to contain_exactly(owner, newbie)
      expect(flash[:alert]).to eq("You are not allowed to perform this action!")
    end

    it "lets the owner and admin remove a member" do
      repo.users << newbie
      content_login!(owner)
      patch remove_member_repositories_path(owner.username),
            params: { repo_owner: { repository_id: repo.id, owner_id: newbie.id } }
      expect(repo.reload.users).to eq([owner])
      expect(flash[:notice]).to eq("This user was removed from your repository.")
      repo.users << newbie
      content_sign_in_as(:admin)
      patch remove_member_repositories_path(owner.username),
            params: { repo_owner: { repository_id: repo.id, owner_id: newbie.id } }
      expect(repo.reload.users).to eq([owner])
    end

    it "remove_member says the user is not a member instead of reporting a removal" do
      repo.users << newbie
      content_login!(owner)
      patch remove_member_repositories_path(owner.username),
            params: { repo_owner: { repository_id: repo.id, owner_id: stranger.id } }
      expect(flash[:alert]).to eq("This user is not a member of this repository.")
      expect(flash[:notice]).to be_nil
      expect(repo.reload.users).to contain_exactly(owner, newbie)
    end

    it "remove_member protects the last member and the owner, and reports unknown users" do
      content_login!(owner)
      patch remove_member_repositories_path(owner.username),
            params: { repo_owner: { repository_id: repo.id, owner_id: owner.id } }
      expect(flash[:alert]).to start_with("You cannot remove the last person")
      repo.users << newbie
      patch remove_member_repositories_path(owner.username),
            params: { repo_owner: { repository_id: repo.id, owner_id: owner.id } }
      expect(flash[:alert]).to eq("You cannot remove the current owner of this repository.")
      patch remove_member_repositories_path(owner.username),
            params: { repo_owner: { repository_id: repo.id, owner_id: 0 } }
      expect(flash[:alert]).to eq("Couldn't find user, please try again.")
    end

    it "transfer_owner IS owner-or-admin gated" do
      repo.users << newbie
      content_login!(stranger)
      patch transfer_owner_repositories_path(owner.username),
            params: { repo_owner: { repository_id: repo.id, owner_id: newbie.id } }
      expect(flash[:alert]).to eq("You don't have the right permissions to perform this action")
      expect(repo.reload.user_id).to eq(owner.id)
    end

    it "transfer_owner moves ownership to a member for the owner and for admin; validates the target" do
      repo.users << newbie
      content_login!(owner)
      patch transfer_owner_repositories_path(owner.username),
            params: { repo_owner: { repository_id: repo.id, owner_id: stranger.id } }
      expect(flash[:alert]).to eq("This user is not a member of your repository.")
      patch transfer_owner_repositories_path(owner.username),
            params: { repo_owner: { repository_id: repo.id, owner_id: owner.id } }
      expect(flash[:alert]).to eq("This user is already the owner of the repository.")
      patch transfer_owner_repositories_path(owner.username),
            params: { repo_owner: { repository_id: repo.id, owner_id: 0 } }
      expect(flash[:alert]).to eq("Couldn't find user, please try again.")
      patch transfer_owner_repositories_path(owner.username),
            params: { repo_owner: { repository_id: repo.id, owner_id: newbie.id } }
      expect(flash[:notice]).to eq("Repository ownership was successfully transferred.")
      expect(repo.reload.user_id).to eq(newbie.id)
    end

    it "refuses a signed-in stranger linking someone else's repository to a project proposal" do
      pp = create(:project_proposal, :approved)
      content_login!(stranger)
      patch link_to_pp_repositories_path(owner.username),
            params: { repo: { repository_id: repo.id, project_proposal_id: pp.id } }
      # link_to_pp is limited to members, staff (as the show page form) and admin
      expect(repo.reload.project_proposal_id).to be_nil
      expect(flash[:alert]).to eq("You are not allowed to perform this action!")
    end

    it "lets the owner, staff and admin link an approved proposal" do
      pp = create(:project_proposal, :approved)
      content_login!(owner)
      patch link_to_pp_repositories_path(owner.username),
            params: { repo: { repository_id: repo.id, project_proposal_id: pp.id } }
      expect(repo.reload.project_proposal_id).to eq(pp.id)
      expect(flash[:notice]).to eq("This Repository was linked to the selected Project Proposal")
      %i[staff admin].each do |role|
        repo.update_columns(project_proposal_id: nil)
        content_sign_in_as(role)
        patch link_to_pp_repositories_path(owner.username),
              params: { repo: { repository_id: repo.id, project_proposal_id: pp.id } }
        expect(repo.reload.project_proposal_id).to eq(pp.id)
      end
    end

    it "refuses to link a proposal that is not approved" do
      pending_pp = create(:project_proposal)
      content_login!(owner)
      patch link_to_pp_repositories_path(owner.username),
            params: { repo: { repository_id: repo.id, project_proposal_id: pending_pp.id } }
      expect(repo.reload.project_proposal_id).to be_nil
      expect(flash[:alert]).to eq("Only an approved Project Proposal can be linked.")
    end

    it "member actions without their params go to the ParameterMissing handler, not a 500 (review)" do
      content_login!(owner)
      {
        add_member_repositories_path(owner.username) => [{}, { repo_owner: "x" }],
        remove_member_repositories_path(owner.username) => [{}, { repo_owner: "x" }],
        link_to_pp_repositories_path(owner.username) => [{}, { repo: "x" }]
      }.each do |path, variants|
        variants.each do |params|
          patch path, params: params
          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to be_present
        end
      end
    end

    it "member actions on an unknown repository raise RecordNotFound" do
      content_login!(owner)
      patch add_member_repositories_path(owner.username),
            params: { repo_owner: { repository_id: 0, owner_username: "x" } }
      expect(response).to have_http_status(:not_found)
    end

    it "member actions on a soft-deleted repository 404 too (default_scope applies to find)" do
      repo.update_columns(deleted: true)
      content_login!(owner)
      patch add_member_repositories_path(owner.username),
            params: { repo_owner: { repository_id: repo.id, owner_username: "x" } }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "a username that does not own the repository" do
    before { content_login!(owner) }

    it "answers 404 to an update through a reserved first segment and changes nothing" do
      patch "/job_orders/#{repo.id}", params: { repository: { title: "Hijacked" } }
      expect(response).to have_http_status(:not_found)
      expect(repo.reload.title).to eq("Laser Lamp")
    end

    it "answers 404 to a delete through a reserved first segment and keeps the repository" do
      expect { delete "/locker_rentals/#{repo.id}" }.not_to change(Repository.unscoped, :count)
      expect(response).to have_http_status(:not_found)
      expect(repo.reload.deleted).to be_falsey
    end

    it "answers 404 to an update, delete, like and edit under another username" do
      patch repository_path(stranger.username, repo.slug), params: { repository: { title: "Hijacked" } }
      expect(response).to have_http_status(:not_found)
      expect { delete repository_path(stranger.username, repo.slug) }.not_to change(Repository.unscoped, :count)
      expect(response).to have_http_status(:not_found)
      expect { post add_like_repository_path(stranger.username, repo.slug) }.not_to change(Like, :count)
      expect(response).to have_http_status(:not_found)
      get edit_repository_path(stranger.username, repo.slug)
      expect(response).to have_http_status(:not_found)
      expect(repo.reload.title).to eq("Laser Lamp")
    end

    it "answers 404 to a view through a reserved first segment" do
      get "/locker_sizes/#{repo.id}"
      expect(response).to have_http_status(:not_found)
    end

    it "still accepts the owner's username in any letter case for an update" do
      patch repository_path(owner.username.upcase, repo.slug), params: { repository: { title: "Renamed" } }
      expect(repo.reload.title).to eq("Renamed")
    end
  end

  describe "GET /repositories/populate_users" do
    # the search term is a token Faker names cannot produce
    let!(:zelda) { create(:user, :regular_user, name: "Zeldaxqzv Searchable") }

    it "routes to repositories#populate_users instead of the show catch-all" do
      # declared above resources :repositories path '/:user_username'
      expect(Rails.application.routes.recognize_path("/repositories/populate_users"))
        .to include(controller: "repositories", action: "populate_users")
    end

    it "sends a guest to login" do
      get "/repositories/populate_users", params: { search: "zeldaxqzv" }
      expect(response.location).to include("/login")
    end

    it "gives a regular user only id and username, matched on username" do
      content_login!(stranger)
      get "/repositories/populate_users", params: { search: "zeldaxqzv" }
      expect(JSON.parse(response.body)["users"]).to be_empty
      get "/repositories/populate_users", params: { search: zelda.username }
      users = JSON.parse(response.body)["users"]
      expect(users).to eq([{ "id" => zelda.id, "username" => zelda.username }])
      expect(response.body).not_to include("Searchable", "password", "access_token", "email")
    end

    it "gives staff id, name and username, matched on name" do
      content_login!(create(:user, :staff))
      get "/repositories/populate_users", params: { search: "zeldaxqzv" }
      expect(JSON.parse(response.body)["users"])
        .to eq([{ "id" => zelda.id, "name" => "Zeldaxqzv Searchable", "username" => zelda.username }])
    end

    it "treats % and _ in the search literally instead of as wildcards (review)" do
      content_login!(create(:user, :staff))
      get "/repositories/populate_users", params: { search: "%" }
      expect(JSON.parse(response.body)["users"]).to be_empty
      get "/repositories/populate_users", params: { search: "Zel_a" }
      expect(JSON.parse(response.body)["users"]).to be_empty
      get "/repositories/populate_users", params: { search: "zeldaxqzv" }
      expect(JSON.parse(response.body)["users"].size).to eq(1)
    end

    it "returns at most 10 users (review)" do
      create_list(:user, 12, :regular_user, name: "Crowd Member")
      content_login!(create(:user, :staff))
      get "/repositories/populate_users", params: { search: "crowd" }
      expect(JSON.parse(response.body)["users"].size).to eq(10)
    end
  end
end
