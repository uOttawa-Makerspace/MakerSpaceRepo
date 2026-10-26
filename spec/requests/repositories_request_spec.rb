# frozen_string_literal: true

require "rails_helper"

# Chunk 16: RepositoriesController (HTTP contract).
#
# Gates: `signed_in` for everything except show/download_files; set_repository
# (id OR slug OR title, soft-deleted rows excluded by Repository's
# default_scope); check_auth (show/download_files: admin, staff, the owner by
# username, or a password the session already passed); check_ownership
# (edit/update/destroy: admin or a member of repository.users).
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

    it "writes the repo into the recently_viewed cookie" do
      get repo_path
      cookie = JSON.parse(CGI.unescape(response.cookies["recently_viewed"]))
      expect(cookie).to eq({ "/#{owner.username}/#{repo.id}" => "Laser Lamp" })
    end

    it "caps recently_viewed at 5 entries (existing entries kept, newcomer dropped past the cap)" do
      get repo_path
      other = create(:repository, owner: owner, title: "Other", users: [owner])
      get repo_path(other)
      expect(JSON.parse(CGI.unescape(response.cookies["recently_viewed"])).keys.size).to eq(2)
    end

    it "does not count as a view anywhere (no counters on the model)" do
      expect { get repo_path }.not_to change { repo.reload.attributes }
    end

    it "finds the repository by id, slug and title, and ignores the username segment (D-C01)" do
      # WART(D-C01): :user_username is never checked against the repository owner, so /anybody/<id> serves any repository
      get repository_path("anybody-at-all", repo.id)
      expect(response).to have_http_status(:ok)
      get repository_path("anybody-at-all", repo.slug)
      expect(response).to have_http_status(:ok)
      get repository_path("anybody-at-all", "Laser Lamp")
      expect(response).to have_http_status(:ok)
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
        expect(response.location).to include("/login")
      end

      it "redirects a signed-in stranger to the password entry page" do
        content_login!(stranger)
        get repo_path(secret)
        expect(response).to redirect_to(password_entry_repository_path(owner.username, secret.id))
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

      it "lets a collaborator (in users, not the owner) in without the password (D-C02)" do
        collaborator = create(:user, :regular_user)
        secret.users << collaborator
        content_login!(collaborator)
        get repo_path(secret)
        # FIXED(D-C02): members of repository.users are authorized like the owner
        expect(response).to have_http_status(:ok)
      end

      it "lets the owner in by user_id even when not in users (D-C02)" do
        secret.users.clear
        content_login!(owner)
        get repo_path(secret)
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "password entry as a guest" do
    let!(:secret) { create(:repository, :private, owner: owner, title: "Secret", users: [owner]) }

    it "password_entry and pass_authenticate need a login: a guest is bounced to /login (D-C16)" do
      get password_entry_repository_path(owner.username, secret.id)
      expect(response).to redirect_to(login_path(back_to: "/#{owner.username}/#{secret.id}/password_entry"))
      post pass_authenticate_repository_path(owner.username, secret.id), params: { password: "open-sesame" }
      # WART(D-C16): show sends guests to the password page, which then sends them to login; guests can never enter a private repo's password
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

    it "a correct password redirects to the slug URL, which is then accepted (D-C03)" do
      post pass_authenticate_repository_path(owner.username, secret.id), params: { password: "open-sesame" }
      expect(response).to redirect_to(repo_path(secret))
      expect(flash[:notice]).to eq("Success")
      follow_redirect!
      # FIXED(D-C03): the session stores the repository id, so the slug URL is recognised
      expect(response).to have_http_status(:ok)
    end

    it "the numeric-id URL is recognised after a correct password" do
      post pass_authenticate_repository_path(owner.username, secret.id), params: { password: "open-sesame" }
      get repository_path(owner.username, secret.id)
      expect(response).to have_http_status(:ok)
    end

    it "authorization is remembered per repository: id, slug and title all pass, other repositories stay locked (D-C03)" do
      other = create(:repository, :private, owner: owner, title: "Other Secret", users: [owner])
      post pass_authenticate_repository_path(owner.username, secret.id), params: { password: "open-sesame" }
      get repository_path(owner.username, secret.id)
      expect(response).to have_http_status(:ok)
      get repository_path(owner.username, secret.title)
      # FIXED(D-C03): whitelist is by repository id, normalised across id/slug/title
      expect(response).to have_http_status(:ok)
      get repo_path(secret)
      expect(response).to have_http_status(:ok)
      get repo_path(other)
      expect(response).to redirect_to(password_entry_repository_path(owner.username, other.id))
    end

    it "pass_authenticate posted to the slug URL also unlocks (D-C03)" do
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

    it "a guest can brute-force the password with no rate limit or lockout (D-C04)" do
      11.times do
        post pass_authenticate_repository_path(owner.username, secret.id), params: { password: "wrong" }
        expect(response).to redirect_to(password_entry_repository_path(owner.username, secret.id))
      end
      # WART(D-C04): no throttling on pass_authenticate
      post pass_authenticate_repository_path(owner.username, secret.id), params: { password: "open-sesame" }
      expect(flash[:notice]).to eq("Success")
    end

    it "pass_authenticate on a public repository redirects to show instead of raising (D-C05)" do
      post pass_authenticate_repository_path(owner.username, repo.id), params: { password: "x" }
      # FIXED(D-C05): a public repository has no password to check; go to show
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

    it "rejects a non-image gallery upload (content-type validation) with 422" do
      content_login!(stranger)
      p = valid_params(title: "BadPic")
      p[:repository][:photos_attributes] = { "0" => { image: content_stl_upload } }
      expect { post repositories_path(stranger.username), params: p }.not_to change(Repository, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "accepts any file type as a repo_file on a repository (the type allow-list only applies to proficient projects) (D-C06)" do
      content_login!(stranger)
      p = valid_params(title: "Files")
      p[:repository][:repo_files_attributes] = { "0" => { file: content_named_upload("evil.exe", type: "application/x-msdownload") } }
      expect { post repositories_path(stranger.username), params: p }.to change(RepoFile, :count).by(1)
      # WART(D-C06): no content-type or size validation for repository files
      expect(RepoFile.last.file.filename.to_s).to eq("evil.exe")
    end

    it "an unparseable youtube link is silently nulled" do
      content_login!(stranger)
      post repositories_path(stranger.username), params: valid_params(title: "Yt", youtube_link: "https://google.ca")
      expect(Repository.find_by(title: "Yt").youtube_link).to be_nil
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

    it "bounces staff (staff can view private repos but not edit)" do
      content_sign_in_as(:staff)
      get edit_repository_path(owner.username, repo.slug)
      expect(response).to redirect_to(repo_path)
    end

    it "lets the repository owner edit when the owner is not in repository.users (D-C07)" do
      orphan = create(:repository, owner: owner, title: "Orphan") # factory: users empty
      content_login!(owner)
      get edit_repository_path(owner.username, orphan.slug)
      # FIXED(D-C07): owner is user_id OR a member of the habtm `users`
      expect(response).to have_http_status(:ok)
    end

    it "lets a collaborator (in users, not the owner) edit, and still bounces a stranger from an orphan repo (D-C07)" do
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

    it "replaces categories and equipment wholesale (destroy_all then recreate)" do
      Category.create!(name: "Old", repository_id: repo.id)
      content_login!(owner)
      patch repository_path(owner.username, repo.slug),
            params: update_params.deep_merge(repository: { categories: %w[New], equipments: [] })
      expect(repo.reload.categories.pluck(:name)).to eq(["New"])
      expect(repo.equipments).to be_empty
    end

    it "destroys categories and equipment BEFORE validating: an invalid update still wipes them (D-C08)" do
      Category.create!(name: "Old", repository_id: repo.id)
      content_login!(owner)
      patch repository_path(owner.username, repo.slug), params: { repository: { title: "" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to eq("Unable to apply the changes.")
      # WART(D-C08): update_destroys categories/equipments before the update is validated
      expect(repo.reload.categories).to be_empty
      expect(repo.title).to eq("Laser Lamp")
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
      # FIXED(D-C09): :user_id removed from repository_params; transfer_owner is the only way
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

    it "HARD deletes for a member (the soft-delete flag is not used here), -25 reputation per member" do
      owner.update!(reputation: 100)
      content_login!(owner)
      expect { delete repository_path(owner.username, repo.slug) }
        .to change(Repository.unscoped, :count).by(-1)
      expect(response).to redirect_to(user_path(owner.username))
      expect(flash[:notice]).to eq("Repository has been successfully deleted.")
      expect(owner.reload.reputation).to eq(75)
    end

    it "removes photos, comments and likes with it" do
      create(:comment, repository: repo, user: stranger)
      create(:like, repository: repo, user: stranger)
      content_sign_in_as(:admin)
      expect { delete repository_path(owner.username, repo.slug) }
        .to change(Comment, :count).by(-1).and change(Like, :count).by(-1).and change(Photo, :count).by(-1)
    end

    it "lets the owner delete a repository whose users list does not include them (D-C07)" do
      orphan = create(:repository, owner: owner, title: "Orphan")
      content_login!(owner)
      expect { delete repository_path(owner.username, orphan.slug) }.to change(Repository, :count).by(-1)
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

    it "lets the owner like their own repository (reputation farming possible) (D-C10)" do
      content_login!(owner)
      post add_like_repository_path(owner.username, repo.slug)
      # WART(D-C10): no self-like guard; likes on your own repo give you +5 reputation
      expect(repo.reload.like).to eq(1)
      expect(owner.reload.reputation).to eq(5)
    end

    it "refuses to like a private repository without its password (D-C11)" do
      secret = create(:repository, :private, owner: owner, title: "Sec", users: [owner])
      content_login!(stranger)
      expect { post add_like_repository_path(owner.username, secret.slug) }.not_to change(Like, :count)
      # FIXED(D-C11): add_like runs the shared private-repository gate
      expect(response).to redirect_to(password_entry_repository_path(owner.username, secret.id))
    end

    it "lets the owner, a collaborator and a user who entered the password like a private repository (D-C11)" do
      secret = create(:repository, :private, owner: owner, title: "Sec", users: [owner])
      secret.update_columns(password: BCrypt::Password.create("open-sesame"))
      collaborator = create(:user, :regular_user)
      secret.users << collaborator
      [owner, collaborator].each do |u|
        content_login!(u)
        post add_like_repository_path(owner.username, secret.slug)
        expect(response).to redirect_to(repo_path(secret))
      end
      expect(Like.where(repository_id: secret.id).count).to eq(2)
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

    it "refuses a signed-in stranger adding a member to someone else's repository (D-C12)" do
      content_login!(stranger)
      patch add_member_repositories_path(owner.username),
            params: { repo_owner: { repository_id: repo.id, owner_username: newbie.username } }
      # FIXED(D-C12): add_member runs check_ownership (owner, member or admin)
      expect(repo.reload.users).to eq([owner])
      expect(flash[:alert]).to eq("You are not allowed to perform this action!")
      expect(response).to redirect_to(repo_path)
    end

    it "lets the owner (even when not in users), a collaborator and admin add a member (D-C12)" do
      orphan = create(:repository, owner: owner, title: "Orphan")
      content_login!(owner)
      patch add_member_repositories_path(owner.username),
            params: { repo_owner: { repository_id: orphan.id, owner_username: newbie.username } }
      expect(orphan.reload.users).to eq([newbie])
      expect(flash[:notice]).to eq("This user was added to your repository.")

      content_login!(newbie) # now a collaborator of orphan
      patch add_member_repositories_path(owner.username),
            params: { repo_owner: { repository_id: orphan.id, owner_username: stranger.username } }
      expect(orphan.reload.users).to contain_exactly(newbie, stranger)

      third = create(:user, :regular_user)
      content_sign_in_as(:admin)
      patch add_member_repositories_path(owner.username),
            params: { repo_owner: { repository_id: orphan.id, owner_username: third.username } }
      expect(orphan.reload.users).to include(third)
    end

    it "refuses staff adding a member (staff are not repository owners) (D-C12)" do
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

    it "refuses a signed-in stranger removing a member from someone else's repository (D-C13)" do
      repo.users << newbie
      content_login!(stranger)
      patch remove_member_repositories_path(owner.username),
            params: { repo_owner: { repository_id: repo.id, owner_id: newbie.id } }
      # FIXED(D-C13): remove_member runs check_ownership
      expect(repo.reload.users).to contain_exactly(owner, newbie)
      expect(flash[:alert]).to eq("You are not allowed to perform this action!")
    end

    it "lets the owner and admin remove a member (D-C13)" do
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

    it "refuses a signed-in stranger linking someone else's repository to a project proposal (D-C14)" do
      pp = create(:project_proposal, :approved)
      content_login!(stranger)
      patch link_to_pp_repositories_path(owner.username),
            params: { repo: { repository_id: repo.id, project_proposal_id: pp.id } }
      # FIXED(D-C14): link_to_pp is limited to members, staff (as the show page form) and admin
      expect(repo.reload.project_proposal_id).to be_nil
      expect(flash[:alert]).to eq("You are not allowed to perform this action!")
    end

    it "lets the owner, staff and admin link an approved proposal (D-C14)" do
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

    it "refuses to link a proposal that is not approved (D-C14)" do
      pending_pp = create(:project_proposal)
      content_login!(owner)
      patch link_to_pp_repositories_path(owner.username),
            params: { repo: { repository_id: repo.id, project_proposal_id: pending_pp.id } }
      expect(repo.reload.project_proposal_id).to be_nil
      expect(flash[:alert]).to eq("Only an approved Project Proposal can be linked.")
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

  describe "GET /repositories/populate_users" do
    it "is unreachable: the /:user_username/:id show route shadows it, so JS callers get a 404 (D-C15)" do
      create(:user, :regular_user, name: "Zelda Searchable")
      get "/repositories/populate_users", params: { search: "zelda" }
      # WART(D-C15): routes.rb declares it after resources :repositories path '/:user_username'; it resolves to repositories#show
      expect(response).to have_http_status(:not_found)
      expect(Rails.application.routes.recognize_path("/repositories/populate_users"))
        .to include(action: "show", user_username: "repositories", id: "populate_users")
    end
  end
end
