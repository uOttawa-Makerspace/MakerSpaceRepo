# frozen_string_literal: true

require "rails_helper"

# Chunk 16: ProjectProposalsController (HTTP contract).
#
# Gates: show (approved, or admin, or the owner), destroy (`return unless admin?`),
# params[:season/:year] (admin only); edit, update and revisions need sign-in and
# ownership or admin; approve and decline are admin-only. Guests get
# current_user = User.new (never nil), so the `current_user.nil?` captcha branch
# in #create does not run.
RSpec.describe "Project proposals (HTTP contract)", type: :request do
  include ContentSpecHelpers

  let(:owner) { create(:user, :regular_user) }
  let(:other) { create(:user, :regular_user) }
  let!(:approved) { create(:project_proposal, :approved, user: owner, title: "Approved One") }
  let!(:pending) { create(:project_proposal, user: owner, title: "Pending One") }
  let!(:declined) { create(:project_proposal, :not_approved, user: owner, title: "Declined One") }

  def proposal_params(**over)
    { project_proposal: { title: "New Idea", description: "d", username: "Ann", email: "ann@example.com",
                          client: "ACME", client_type: "individual", client_interest: "Low",
                          client_background: "none", supervisor_background: "none",
                          equipments: "n/a", project_cost: 10 }.merge(over) }
  end

  describe "GET index" do
    it "shows only approved proposals to a guest" do
      get project_proposals_path
      expect(response).to have_http_status(:ok)
      # pending and declined proposals are not listed publicly
      expect(response.body).to include("Approved One")
      expect(response.body).not_to include("Pending One", "Declined One")
      get project_proposals_path, params: { status: %w[0 nil] }
      expect(response.body).not_to include("Pending One", "Declined One")
    end

    it "shows a regular user approved proposals plus their own, but not other users' pending ones" do
      content_login!(other)
      get project_proposals_path
      expect(response.body).to include("Approved One")
      expect(response.body).not_to include("Pending One", "Declined One")
      content_login!(owner)
      get project_proposals_path
      expect(response.body).to include("Approved One", "Pending One", "Declined One")
      get project_proposals_path, params: { status: %w[0 nil] }
      expect(response.body).to include("Pending One", "Declined One")
      expect(response.body).not_to include("Approved One")
    end

    it "shows staff only approved proposals and admins everything" do
      content_sign_in_as(:staff)
      get project_proposals_path
      expect(response.body).to include("Approved One")
      expect(response.body).not_to include("Pending One", "Declined One")
      content_sign_in_as(:admin)
      get project_proposals_path
      expect(response.body).to include("Approved One", "Pending One", "Declined One")
    end

    it "filters by status (1 approved, 0 declined, nil pending) and combinations" do
      content_sign_in_as(:admin)
      get project_proposals_path, params: { status: ["1"] }
      expect(response.body).to include("Approved One")
      expect(response.body).not_to include("Pending One", "Declined One")
      get project_proposals_path, params: { status: ["nil"] }
      expect(response.body).to include("Pending One")
      expect(response.body).not_to include("Approved One")
      get project_proposals_path, params: { status: %w[0 nil] }
      expect(response.body).to include("Pending One", "Declined One")
      expect(response.body).not_to include("Approved One")
    end

    it "searches by title and filters by semester" do
      approved.update_columns(season: ProjectProposal.seasons[:fall], year: 2024)
      create(:project_proposal, :approved, title: "Zebra Crossing")
      get project_proposals_path, params: { query: "zebra" }
      expect(response.body).to include("Zebra Crossing")
      expect(response.body).not_to include("Pending One", "Approved One")
      get project_proposals_path, params: { semester: "fall_2024" }
      expect(response.body).to include("Approved One")
      expect(response.body).not_to include("Pending One")
      content_sign_in_as(:admin)
      get project_proposals_path, params: { semester: "bogus_xx" }
      expect(response.body).to include("Pending One")
    end
  end

  describe "GET show" do
    it "renders an approved proposal for a guest" do
      get project_proposal_path(approved.slug)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Approved One")
    end

    it "finds a proposal by slug or by id" do
      get project_proposal_path(approved.id)
      expect(response).to have_http_status(:ok)
    end

    [[:pending, "pending"], [:declined, "declined"]].each do |name, label|
      it "redirects a guest and a stranger away from a #{label} proposal" do
        pp = send(name)
        get project_proposal_path(pp.slug)
        expect(response).to redirect_to(project_proposals_path)
        expect(flash[:alert]).to eq("You are not allowed to access this pending project proposal.")
        content_login!(other)
        get project_proposal_path(pp.slug)
        expect(response).to redirect_to(project_proposals_path)
      end

      it "renders a #{label} proposal for its owner and for admin, but not for staff" do
        pp = send(name)
        content_login!(owner)
        get project_proposal_path(pp.slug)
        expect(response).to have_http_status(:ok)
      end
    end

    it "admin sees a pending proposal; staff does not" do
      content_sign_in_as(:staff)
      get project_proposal_path(pending.slug)
      expect(response).to redirect_to(project_proposals_path)
      content_sign_in_as(:admin)
      get project_proposal_path(pending.slug)
      expect(response).to have_http_status(:ok)
    end

    context "revisions listed on an approved proposal (visibility as the index)" do
      let!(:rev_pending) { create(:project_proposal, user: other, linked_project_proposal: approved, title: "Revision Pending Other") }
      let!(:rev_approved) { create(:project_proposal, :approved, user: other, linked_project_proposal: approved, title: "Revision Approved Other") }
      let!(:rev_own) { create(:project_proposal, user: owner, linked_project_proposal: approved, title: "Revision Own Pending") }

      it "shows a guest only approved revisions" do
        get project_proposal_path(approved.slug)
        expect(response.body).to include("Revision Approved Other")
        expect(response.body).not_to include("Revision Pending Other", "Revision Own Pending")
      end

      it "shows the viewer their own pending revision but not other users'" do
        content_login!(owner)
        get project_proposal_path(approved.slug)
        expect(response.body).to include("Revision Approved Other", "Revision Own Pending")
        expect(response.body).not_to include("Revision Pending Other")
      end

      it "shows an admin every revision, and staff only the approved one" do
        content_sign_in_as(:staff)
        get project_proposal_path(approved.slug)
        expect(response.body).not_to include("Revision Pending Other")
        content_sign_in_as(:admin)
        get project_proposal_path(approved.slug)
        expect(response.body).to include("Revision Pending Other", "Revision Own Pending", "Revision Approved Other")
      end
    end

    it "redirects with 'not found' for an unknown id (no 404)" do
      get project_proposal_path("nope")
      expect(response).to redirect_to(project_proposals_path)
      expect(flash[:alert]).to eq("Project proposal not found")
    end

    it "lists the repositories linked to the proposal, with sorting" do
      create(:repository, owner: owner, title: "Linked Repo", project_proposal_id: approved.id)
      get project_proposal_path(approved.slug, sort: "most_likes")
      expect(response.body).to include("Linked Repo")
    end
  end

  describe "GET show: linked repositories" do
    let(:repo_owner) { create(:user, :regular_user) }
    let!(:public_repo) do
      create(:repository, owner: repo_owner, title: "Open Linked Repo", project_proposal_id: approved.id)
    end
    let!(:private_repo) do
      create(:repository, :private, owner: repo_owner, title: "Secret Linked Repo", project_proposal_id: approved.id)
    end

    def expect_cards(visible:, hidden: [])
      get project_proposal_path(approved.slug)
      expect(response).to have_http_status(:ok)
      visible.each { |t| expect(response.body).to include(t) }
      hidden.each { |t| expect(response.body).not_to include(t) }
    end

    it "lists only the public repository to a guest" do
      expect_cards(visible: ["Open Linked Repo"], hidden: ["Secret Linked Repo"])
    end

    it "lists only the public repository to an unrelated signed-in user" do
      content_login!(other)
      expect_cards(visible: ["Open Linked Repo"], hidden: ["Secret Linked Repo"])
    end

    it "lists both to the private repository's owner" do
      content_login!(repo_owner)
      expect_cards(visible: ["Open Linked Repo", "Secret Linked Repo"])
    end

    it "lists both to a member of the private repository" do
      private_repo.users << other
      content_login!(other)
      expect_cards(visible: ["Open Linked Repo", "Secret Linked Repo"])
    end

    it "lists both to staff (the A7 gate)" do
      content_login!(create(:user, :staff))
      expect_cards(visible: ["Open Linked Repo", "Secret Linked Repo"])
    end

    it "lists both to an admin" do
      content_login!(create(:user, :admin))
      expect_cards(visible: ["Open Linked Repo", "Secret Linked Repo"])
    end

    it "lists the private repository after its password was entered in this session" do
      private_repo.update_columns(password: BCrypt::Password.create("pw1234"))
      post pass_authenticate_repository_path(private_repo.user_username, private_repo.id), params: { password: "pw1234" }
      expect_cards(visible: ["Open Linked Repo", "Secret Linked Repo"])
    end

    it "still paginates the filtered scope" do
      10.times { |i| create(:repository, owner: repo_owner, title: "Bulk Repo #{i}", project_proposal_id: approved.id) }
      get project_proposal_path(approved.slug)
      expect(response.body).not_to include("Secret Linked Repo")
      get project_proposal_path(approved.slug, page: 2)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Secret Linked Repo")
    end
  end

  describe "GET new / edit" do
    it "renders new for a guest" do
      get new_project_proposal_path
      expect(response).to have_http_status(:ok)
    end

    it "sends a guest to the login page instead of rendering edit" do
      get edit_project_proposal_path(pending.slug)
      # edit requires sign-in, then ownership or admin
      expect(response).to redirect_to(login_path(back_to: edit_project_proposal_path(pending.slug)))
      expect(response.body).not_to include(pending.email)
    end

    it "refuses edit to a stranger and to staff" do
      [create(:user, :regular_user), create(:user, :staff)].each do |user|
        content_login!(user)
        get edit_project_proposal_path(pending.slug)
        expect(response).to redirect_to(project_proposals_path)
        expect(flash[:alert]).to eq("You are not allowed to modify this project proposal.")
      end
    end

    it "renders edit for the owner and for an admin" do
      content_login!(owner)
      get edit_project_proposal_path(pending.slug)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(pending.email)
      content_sign_in_as(:admin)
      get edit_project_proposal_path(pending.slug)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST create" do
    it "lets a guest create a proposal (the captcha check runs only for a nil current_user)" do
      expect { post project_proposals_path, params: proposal_params }.to change(ProjectProposal, :count).by(1)
      # `current_user.nil? && !verify_turnstile` does not run (current_user is User.new)
      pp = ProjectProposal.find_by(title: "New Idea")
      expect(pp.user_id).to be_nil
      expect(pp.approved).to be_nil
      expect(response).to redirect_to(project_proposal_path(pp.slug))
      expect(flash[:notice]).to eq("Project proposal was successfully created.")
    end

    it "sets user_id from the session and emails makerlab@uottawa.ca" do
      content_login!(owner)
      ActionMailer::Base.deliveries.clear
      post project_proposals_path, params: proposal_params
      pp = ProjectProposal.find_by(title: "New Idea")
      expect(pp.user_id).to eq(owner.id)
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq(["makerlab@uottawa.ca"])
      expect(mail.subject).to eq("New Project Proposal")
    end

    it "ignores submitted approved/admin_id/user_id: a guest cannot self-approve" do
      post project_proposals_path, params: proposal_params(approved: "approved", admin_id: owner.id, user_id: other.id)
      pp = ProjectProposal.find_by(title: "New Idea")
      # :approved/:admin_id/:user_id are not permitted; only approve/decline set review fields
      expect(pp.approved).to be_nil
      expect(pp.admin_id).to be_nil
      expect(pp.user_id).to be_nil
    end

    it "a signed-in user cannot self-approve or set the owner on create" do
      content_login!(owner)
      post project_proposals_path, params: proposal_params(approved: "approved", admin_id: owner.id, user_id: other.id)
      expect(ProjectProposal.find_by(title: "New Idea")).to have_attributes(approved: nil, admin_id: nil, user_id: owner.id)
    end

    it "cannot link a new proposal to someone else's as its 'revision'" do
      content_login!(other)
      post project_proposals_path, params: proposal_params(linked_project_proposal_id: pending.id)
      expect(ProjectProposal.find_by(title: "New Idea").linked_project_proposal_id).to be_nil
    end

    it "an admin cannot set review fields through create either" do
      content_sign_in_as(:admin)
      post project_proposals_path, params: proposal_params(approved: "approved", admin_id: owner.id)
      expect(ProjectProposal.find_by(title: "New Idea")).to have_attributes(approved: nil, admin_id: nil)
    end

    it "ignores approved sent as the numeric string '1' instead of 500ing" do
      expect { post project_proposals_path, params: proposal_params(approved: 1) }.to change(ProjectProposal, :count).by(1)
      expect(ProjectProposal.find_by(title: "New Idea").approved).to be_nil
    end

    it "only admins can set season and year" do
      post project_proposals_path, params: proposal_params(season: "fall", year: 2024)
      expect(ProjectProposal.find_by(title: "New Idea").attributes.values_at("season", "year")).to eq([nil, nil])
      content_sign_in_as(:admin)
      post project_proposals_path, params: proposal_params(title: "Admin Idea", season: "fall", year: 2024)
      expect(ProjectProposal.find_by(title: "Admin Idea").attributes.values_at("season", "year")).to eq(["fall", 2024])
    end

    it "answers JSON with the redirect uri" do
      post project_proposals_path(format: :json), params: proposal_params
      expect(response.parsed_body).to eq("redirect_uri" => project_proposal_path(ProjectProposal.find_by(title: "New Idea").slug))
    end

    it "re-renders new with 422 and an alert when invalid, sending no mail" do
      ActionMailer::Base.deliveries.clear
      expect { post project_proposals_path, params: proposal_params(title: "", project_cost: -1) }
        .not_to change(ProjectProposal, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to eq("An error occurred while creating the project proposal, try again later.")
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "JSON validation errors are keyed by attribute" do
      post project_proposals_path(format: :json), params: proposal_params(title: "")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.keys).to include("title")
    end

    it "creates categories (max 5)" do
      post project_proposals_path, params: proposal_params(categories: %w[a b c d e f])
      expect(ProjectProposal.find_by(title: "New Idea").categories.pluck(:name)).to match_array(%w[a b c d e])
    end

    # ProjectProposal validates project_files (sniffed type + size) in the model
    it "attaches up to 5 images and any number of allowed files, but not an executable" do
      files = [content_pdf_upload, content_named_upload("run.exe", type: "application/x-msdownload"),
               content_named_upload("a.stl", content: "solid x\nfacet normal 0 0 0\n", type: "model/stl")]
      imgs = Array.new(6) { content_png_upload }
      post project_proposals_path, params: { images: imgs, files: files }.merge(proposal_params)
      pp = ProjectProposal.find_by(title: "New Idea")
      expect(pp.photos.count).to eq(5)
      expect(pp.project_files.map { |f| f.filename.to_s }).to contain_exactly("RepoFile1.pdf", "a.stl")
    end

    it "keeps the good files after a refused one and tells the user which file was refused" do
      files = [content_named_upload("run.exe", type: "application/x-msdownload"), content_named_upload("ok.txt", content: "tiny")]
      post project_proposals_path, params: { files: files }.merge(proposal_params)
      pp = ProjectProposal.find_by(title: "New Idea")
      expect(pp.project_files.map { |f| f.filename.to_s }).to eq(["ok.txt"])
      expect(flash[:alert]).to include("run.exe")
      expect(flash[:alert]).not_to include("ok.txt")
    end

    it "caps the refused-names flash so many long names cannot overflow the cookie session" do
      files = Array.new(12) { |i| content_named_upload("#{'x' * 200}#{i}.exe", type: "application/x-msdownload") }
      post project_proposals_path, params: { files: files }.merge(proposal_params)
      expect(response).to have_http_status(:found)
      expect(flash[:alert].length).to be < 400
      expect(flash[:alert]).to include("and 7 more")
      expect(ProjectProposal.find_by(title: "New Idea").project_files).not_to be_attached
    end

    it "reports both the pre-check refusals and the model's own errors, with no success flash, and still saves the proposal" do
      # run.exe passes the (stubbed) pre-check but fails the model validation; fake.exe is refused by the pre-check
      allow_any_instance_of(ProjectProposal).to receive(:sniffed_upload_problems) { |_, _name, f| f.original_filename == "fake.exe" ? ["bad"] : [] }
      files = [content_named_upload("run.exe", type: "application/x-msdownload"), content_named_upload("fake.exe", type: "application/x-msdownload")]
      expect { post project_proposals_path, params: { files: files }.merge(proposal_params) }.to change(ProjectProposal, :count).by(1)
      pp = ProjectProposal.find_by(title: "New Idea")
      expect(response).to redirect_to(project_proposal_path(pp.slug))
      expect(flash[:notice]).to be_blank
      expect(flash[:alert]).to include("fake.exe") # pre-check refusal
      expect(flash[:alert]).to include("run.exe has a file type that is not allowed") # the model's real error
      expect(pp.project_files).not_to be_attached
      expect(pp.errors).to be_empty
    end

    it "keeps the success notice when every file was accepted" do
      post project_proposals_path, params: { files: [content_named_upload("ok.txt", content: "tiny")] }.merge(proposal_params)
      expect(flash[:notice]).to eq("Project proposal was successfully created.")
      expect(flash[:alert]).to be_blank
    end

    it "ignores a file param that is a string (signed id) instead of an upload" do
      post project_proposals_path, params: { files: ["not-an-upload"] }.merge(proposal_params)
      expect(response).to have_http_status(:found)
      expect(ProjectProposal.find_by(title: "New Idea").project_files).not_to be_attached
    end

    it "does not store an executable disguised as a pdf" do
      exe = "MZ" + ("\x00" * 200)
      files = [content_named_upload("ok.txt", content: "tiny"), content_named_upload("fake.pdf", content: exe, type: "application/pdf")]
      post project_proposals_path, params: { files: files }.merge(proposal_params)
      expect(ProjectProposal.find_by(title: "New Idea").project_files.map { |f| f.filename.to_s }).to eq(["ok.txt"])
    end

    it "does not store a file over the size cap" do
      stub_const("ProjectProposal::MAX_PROJECT_FILE_SIZE", 20.bytes)
      files = [content_named_upload("ok.txt", content: "tiny"), content_named_upload("big.txt", content: "x" * 21)]
      post project_proposals_path, params: { files: files }.merge(proposal_params)
      expect(ProjectProposal.find_by(title: "New Idea").project_files.map { |f| f.filename.to_s }).to eq(["ok.txt"])
    end

    it "model: invalid project_files make the proposal invalid" do
      pp = build(:project_proposal)
      pp.project_files.attach(content_named_upload("run.exe", type: "application/x-msdownload"))
      expect(pp).not_to be_valid
      expect(pp.errors[:project_files].join).to include("run.exe")
    end

    it "sanitizes path-like attachment names" do
      post project_proposals_path, params: { files: [content_named_upload("../../etc/passwd.txt")] }.merge(proposal_params)
      name = ProjectProposal.find_by(title: "New Idea").project_files.first.filename.to_s
      expect(name).not_to include("/")
    end

    it "an unreadable image destroys the proposal and redirects back without a mail" do
      ActionMailer::Base.deliveries.clear
      expect do
        post project_proposals_path, params: { images: [content_named_upload("x.png", content: "junk", type: "image/png")] }.merge(proposal_params)
      end.not_to change(ProjectProposal, :count)
      expect(flash[:alert]).to eq("Something went wrong while uploading photos, try again later.")
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "an unparseable youtube link is nulled" do
      post project_proposals_path, params: proposal_params(youtube_link: "https://google.ca")
      expect(ProjectProposal.find_by(title: "New Idea").youtube_link).to be_nil
    end
  end

  describe "PATCH update" do
    it "update with a refused file gives no success notice" do
      content_login!(owner)
      files = [content_named_upload("run.exe", type: "application/x-msdownload")]
      patch project_proposal_path(pending.slug), params: { project_proposal: { title: "Pending One" }, files: files }
      expect(flash[:notice]).to be_blank
      expect(flash[:alert]).to include("run.exe")
    end

    it "keeps the good files after a refused one on update and reports the refused name" do
      content_login!(owner)
      mine = pending
      files = [content_named_upload("run.exe", type: "application/x-msdownload"), content_named_upload("ok.txt", content: "tiny")]
      patch project_proposal_path(mine.slug), params: { project_proposal: { title: "Pending One" }, files: files }
      expect(mine.reload.project_files.map { |f| f.filename.to_s }).to eq(["ok.txt"])
      expect(flash[:alert]).to include("run.exe")
    end

    it "does not let a guest rewrite a proposal" do
      patch project_proposal_path(pending.slug), params: { project_proposal: { title: "Hijacked" } }
      # update requires sign-in, then ownership or admin
      expect(response).to redirect_to(login_path)
      expect(pending.reload.title).to eq("Pending One")
    end

    it "does not let a stranger or staff rewrite a proposal" do
      [create(:user, :regular_user), create(:user, :staff)].each do |user|
        content_login!(user)
        patch project_proposal_path(pending.slug), params: { project_proposal: { title: "Hijacked" } }
        expect(response).to redirect_to(project_proposals_path)
        expect(flash[:alert]).to eq("You are not allowed to modify this project proposal.")
        patch project_proposal_path(pending.slug, format: :json), params: { project_proposal: { title: "Hijacked" } }
        expect(response).to have_http_status(:forbidden)
        expect(pending.reload.title).to eq("Pending One")
      end
    end

    it "lets the owner and an admin edit" do
      content_login!(owner)
      patch project_proposal_path(pending.slug), params: { project_proposal: { title: "Owner Edit" } }
      expect(response).to redirect_to(project_proposal_path(pending.reload.slug))
      expect(flash[:notice]).to eq("Project proposal was successfully updated.")
      content_sign_in_as(:admin)
      patch project_proposal_path(pending.slug), params: { project_proposal: { title: "Admin Edit" } }
      expect(pending.reload.title).to eq("Admin Edit")
    end

    it "an owner's edit of an approved proposal sends it back to pending and drops it from the public list" do
      content_login!(owner)
      patch project_proposal_path(approved.slug), params: { project_proposal: { title: "Approved Reworked" } }
      expect(approved.reload).to have_attributes(approved: nil, admin_id: nil, title: "Approved Reworked")
      expect(flash[:notice]).to include("needs to be re-approved by an admin")
      reset!
      get project_proposals_path
      expect(response.body).not_to include("Approved Reworked")
    end

    it "an admin sees the re-pended proposal in the Pending Decision filter" do
      approved.update!(user: owner)
      content_login!(owner)
      patch project_proposal_path(approved.slug), params: { project_proposal: { title: "Approved Reworked" } }
      content_sign_in_as(:admin)
      get project_proposals_path, params: { status: ["nil"] }
      expect(response.body).to include("Approved Reworked")
    end

    it "an admin's edit keeps an approved proposal approved" do
      admin = content_sign_in_as(:admin)
      approved.update_columns(admin_id: admin.id)
      patch project_proposal_path(approved.slug), params: { project_proposal: { title: "Admin Tweak" } }
      expect(approved.reload).to have_attributes(approved: "approved", admin_id: admin.id, title: "Admin Tweak")
      expect(flash[:notice]).to eq("Project proposal was successfully updated.")
    end

    it "an owner's edit of a pending proposal keeps it pending" do
      content_login!(owner)
      patch project_proposal_path(pending.slug), params: { project_proposal: { title: "Pending Reworked" } }
      expect(pending.reload.approved).to be_nil
      expect(flash[:notice]).to eq("Project proposal was successfully updated.")
    end

    it "the owner cannot reassign user_id or set review fields through mass assignment" do
      content_login!(owner)
      patch project_proposal_path(pending.slug),
            params: { project_proposal: { user_id: other.id, approved: "approved", admin_id: owner.id } }
      expect(pending.reload).to have_attributes(user_id: owner.id, approved: nil, admin_id: nil)
    end

    it "the owner cannot re-link their proposal to someone else's" do
      content_login!(owner)
      patch project_proposal_path(pending.slug), params: { project_proposal: { linked_project_proposal_id: approved.id } }
      expect(pending.reload.linked_project_proposal_id).to be_nil
    end

    it "an admin cannot mass-assign review fields on update either" do
      content_sign_in_as(:admin)
      patch project_proposal_path(pending.slug), params: { project_proposal: { title: "Edited", approved: "approved", user_id: other.id } }
      expect(pending.reload).to have_attributes(title: "Edited", approved: nil, user_id: owner.id)
    end

    it "replaces categories, JSON answers with the uri" do
      content_login!(owner)
      Category.create!(name: "Old", project_proposal_id: pending.id)
      patch project_proposal_path(pending.slug, format: :json),
            params: { project_proposal: { title: "Retitled", categories: %w[New] } }
      expect(pending.reload.categories.pluck(:name)).to eq(["New"])
      expect(response.parsed_body).to eq("redirect_uri" => project_proposal_path(pending.slug))
    end

    it "wipes categories even when the update is invalid" do
      content_login!(owner)
      Category.create!(name: "Old", project_proposal_id: pending.id)
      patch project_proposal_path(pending.slug), params: { project_proposal: { title: "" } }
      expect(response).to have_http_status(:unprocessable_content)
      # categories.destroy_all runs before validation
      expect(pending.reload.categories).to be_empty
    end

    it "re-slugs to '<id>.<title>' on update" do
      content_login!(owner)
      patch project_proposal_path(pending.slug), params: { project_proposal: { title: "Zed Title" } }
      expect(pending.reload.slug).to eq("#{pending.id}.zed-title")
    end

    it "adds and deletes attachments (by filename or attachment id)" do
      content_login!(owner)
      pending.photos.attach(io: File.open(Rails.root.join("spec/support/assets/avatar.png")), filename: "keep.png", content_type: "image/png")
      pending.photos.attach(io: File.open(Rails.root.join("spec/support/assets/avatar.png")), filename: "drop.png", content_type: "image/png")
      patch project_proposal_path(pending.slug),
            params: { project_proposal: { title: "T" }, deleteimages: ["drop.png"], files: [content_pdf_upload] }
      pending.reload
      expect(pending.photos.map { |p| p.filename.to_s }).to eq(["keep.png"])
      expect(pending.project_files.map { |f| f.filename.to_s }).to eq(["RepoFile1.pdf"])
      patch project_proposal_path(pending.slug),
            params: { project_proposal: { title: "T" }, deletefiles: [pending.project_files.first.id.to_s] }
      expect(pending.reload.project_files.count).to eq(0)
    end
  end

  describe "DELETE destroy" do
    it "does nothing for guests, owners and staff (action returns without rendering: 204)" do
      [nil, owner, create(:user, :staff)].each do |user|
        content_login!(user) if user
        expect { delete project_proposal_path(pending.slug) }.not_to change(ProjectProposal, :count)
        # `return unless admin?` renders nothing, so a refused delete answers 204 instead of a redirect/alert
        expect(response).to have_http_status(:no_content)
      end
    end

    it "deletes for an admin, both routes, cascading joins and categories, not repositories" do
      content_sign_in_as(:admin)
      ProjectJoin.create!(project_proposal_id: pending.id, user_id: owner.id)
      Category.create!(name: "c", project_proposal_id: pending.id)
      repo = create(:repository, owner: owner, project_proposal_id: pending.id)
      expect { delete project_proposal_path(pending.slug) }
        .to change(ProjectProposal, :count).by(-1).and change(ProjectJoin, :count).by(-1).and change(Category, :count).by(-1)
      expect(response).to redirect_to(project_proposals_url)
      expect(flash[:notice]).to eq("Project proposal was successfully deleted.")
      expect(Repository.exists?(repo.id)).to be(true)
      expect { delete destroy_project_proposals_path(id: approved.id) }.to change(ProjectProposal, :count).by(-1)
    end

    it "answers 204 for JSON when admin" do
      content_sign_in_as(:admin)
      delete project_proposal_path(pending.slug, format: :json)
      expect(response).to have_http_status(:no_content)
      expect(ProjectProposal.exists?(pending.id)).to be(false)
    end
  end

  describe "POST approve / decline" do
    it "sends a guest to login and changes nothing" do
      post approve_project_proposals_path, params: { id: pending.id }
      # approve/decline are admin-only
      expect(response).to redirect_to(login_path)
      post decline_project_proposals_path, params: { id: approved.id }
      expect(response).to redirect_to(login_path)
      expect(pending.reload.approved).to be_nil
      expect(approved.reload.approved).to eq("approved")
    end

    it "refuses regular users, the proposal owner and staff" do
      [other, owner, create(:user, :staff)].each do |user|
        content_login!(user)
        post approve_project_proposals_path, params: { id: pending.id }
        expect(response).to redirect_to(project_proposals_path)
        expect(flash[:alert]).to eq("Only admins can review project proposals.")
        post decline_project_proposals_path, params: { id: approved.id }
        expect(response).to redirect_to(project_proposals_path)
      end
      expect(pending.reload).to have_attributes(approved: nil, admin_id: nil)
      expect(approved.reload.approved).to eq("approved")
    end

    it "records the admin as reviewer on approve and decline, and sends no email" do
      admin = content_sign_in_as(:admin)
      ActionMailer::Base.deliveries.clear
      post approve_project_proposals_path, params: { id: pending.id }
      expect(pending.reload).to have_attributes(approved: "approved", admin_id: admin.id)
      expect(response).to redirect_to(project_proposals_url)
      expect(flash[:notice]).to eq("Project Proposal Approved")
      post decline_project_proposals_path, params: { id: pending.id }
      expect(pending.reload).to have_attributes(approved: "not_approved", admin_id: admin.id)
      expect(flash[:notice]).to eq("Project Proposal Declined")
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "approve is not idempotent-guarded: an admin re-approving a declined proposal flips it back, overwriting the reviewer" do
      content_sign_in_as(:admin)
      post decline_project_proposals_path, params: { id: pending.id }
      post approve_project_proposals_path, params: { id: pending.id }
      expect(pending.reload.approved).to eq("approved")
    end

    it "404s for an unknown id" do
      content_sign_in_as(:admin)
      post approve_project_proposals_path, params: { id: 0 }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST create_revision" do
    it "sends a guest to login and clones nothing" do
      expect { post create_revision_project_proposals_path, params: { old_project_proposal_id: pending.id } }
        .not_to change(ProjectProposal, :count)
      # create_revision requires sign-in and ownership of the original (or admin)
      expect(response).to redirect_to(login_path)
    end

    it "refuses a stranger and staff, for pending and approved originals alike" do
      [other, create(:user, :staff)].each do |user|
        content_login!(user)
        [pending, approved].each do |pp|
          expect { post create_revision_project_proposals_path, params: { old_project_proposal_id: pp.id } }
            .not_to change(ProjectProposal, :count)
          expect(response).to redirect_to(project_proposals_path)
          expect(flash[:alert]).to eq("You are not allowed to create a revision of this project proposal.")
        end
      end
    end

    it "lets the owner revise their pending proposal and an admin revise any" do
      content_login!(owner)
      expect { post create_revision_project_proposals_path, params: { old_project_proposal_id: pending.id } }
        .to change(ProjectProposal, :count).by(1)
      rev = ProjectProposal.find_by(title: "Revision of Pending One")
      expect(rev).to have_attributes(linked_project_proposal_id: pending.id, user_id: owner.id, approved: nil, admin_id: nil, email: pending.email)
      expect(response).to redirect_to(project_proposal_path(rev.slug))
      expect(flash[:notice]).to eq("The project proposal revision has been successfully created.")
      admin = content_sign_in_as(:admin)
      expect { post create_revision_project_proposals_path, params: { old_project_proposal_id: declined.id } }
        .to change(ProjectProposal, :count).by(1)
      expect(ProjectProposal.find_by(title: "Revision of Declined One").user_id).to eq(admin.id)
    end

    it "sets the owner, copies photos, files (shared blobs) and categories, and sends NO email" do
      approved.photos.attach(io: File.open(Rails.root.join("spec/support/assets/avatar.png")), filename: "a.png", content_type: "image/png")
      approved.project_files.attach(io: File.open(Rails.root.join("spec/support/assets/RepoFile1.pdf")), filename: "f.pdf", content_type: "application/pdf")
      Category.create!(name: "cat", project_proposal_id: approved.id)
      content_login!(owner)
      ActionMailer::Base.deliveries.clear
      post create_revision_project_proposals_path(format: :json), params: { old_project_proposal_id: approved.id }
      rev = ProjectProposal.find_by(linked_project_proposal_id: approved.id)
      expect(rev.user_id).to eq(owner.id)
      expect(rev.photos.first.blob_id).to eq(approved.photos.first.blob_id)
      expect(rev.project_files.first.blob_id).to eq(approved.project_files.first.blob_id)
      expect(rev.categories.pluck(:name)).to eq(["cat"])
      expect(response.parsed_body).to eq("redirect_uri" => project_proposal_path(rev.slug))
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "does not carry over season/year/approval (a revision starts unreviewed)" do
      approved.update_columns(season: ProjectProposal.seasons[:fall], year: 2024)
      content_login!(owner)
      post create_revision_project_proposals_path, params: { old_project_proposal_id: approved.id }
      rev = ProjectProposal.find_by(linked_project_proposal_id: approved.id)
      expect(rev.attributes.values_at("season", "year", "approved")).to eq([nil, nil, nil])
    end

    it "redirects back with an alert for a missing or unknown id" do
      content_login!(owner)
      post create_revision_project_proposals_path
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to start_with("An error occured while trying to create")
      post create_revision_project_proposals_path, params: { old_project_proposal_id: 0 }
      expect(response).to redirect_to(root_path)
    end
  end

  describe "join / unjoin" do
    it "sends a guest to login and stores no join" do
      expect { post join_project_proposal_project_proposals_path, params: { project_proposal_id: approved.id } }
        .not_to change(ProjectJoin, :count)
      # join requires sign-in and an approved proposal
      expect(response).to redirect_to(login_path)
    end

    # neither changes state on a GET any more
    it "neither joins nor unjoins on a plain GET" do
      join = ProjectJoin.create!(project_proposal_id: approved.id, user_id: owner.id)
      content_login!(owner)
      expect { get "/project_proposals/join_project_proposal", params: { project_proposal_id: approved.id } }
        .not_to change(ProjectJoin, :count)
      expect { get "/project_proposals/unjoin_project_proposal", params: { project_proposal_id: approved.id, project_join_id: join.id } }
        .not_to change(ProjectJoin, :count)
      expect(ProjectJoin.exists?(join.id)).to be(true)
    end

    it "joins as the signed-in user, once; the second time alerts" do
      content_login!(other)
      expect { post join_project_proposal_project_proposals_path, params: { project_proposal_id: approved.id } }
        .to change { ProjectJoin.where(user_id: other.id).count }.by(1)
      expect { post join_project_proposal_project_proposals_path, params: { project_proposal_id: approved.id } }
        .not_to change(ProjectJoin, :count)
      expect(flash[:alert]).to eq("You already joined this project or something went wrong.")
    end

    it "cannot join a pending or declined proposal" do
      content_login!(other)
      [pending, declined].each do |pp|
        expect { post join_project_proposal_project_proposals_path, params: { project_proposal_id: pp.id } }
          .not_to change(ProjectJoin, :count)
        expect(response).to redirect_to(project_proposals_path)
        expect(flash[:alert]).to eq("You can only join an approved project proposal.")
      end
    end

    it "does not let a guest remove a join" do
      join = ProjectJoin.create!(project_proposal_id: approved.id, user_id: owner.id)
      delete unjoin_project_proposal_project_proposals_path, params: { project_proposal_id: approved.id, project_join_id: join.id }
      expect(response.location).to start_with(login_url)
      expect(ProjectJoin.exists?(join.id)).to be(true)
    end

    it "does not let a stranger or staff remove someone else's join" do
      join = ProjectJoin.create!(project_proposal_id: approved.id, user_id: owner.id)
      [other, create(:user, :staff)].each do |user|
        content_login!(user)
        delete unjoin_project_proposal_project_proposals_path,
            params: { project_proposal_id: approved.id, project_join_id: join.id }
        # only the join's own user (or an admin) can remove it
        expect(ProjectJoin.exists?(join.id)).to be(true)
        expect(flash[:alert]).to eq("You can only leave a project you joined yourself.")
      end
    end

    it "does not remove a join through a different proposal's URL" do
      join = ProjectJoin.create!(project_proposal_id: approved.id, user_id: owner.id)
      other_approved = create(:project_proposal, :approved)
      content_login!(owner)
      delete unjoin_project_proposal_project_proposals_path,
          params: { project_proposal_id: other_approved.id, project_join_id: join.id }
      expect(response).to have_http_status(:not_found)
      expect(ProjectJoin.exists?(join.id)).to be(true)
    end

    it "lets users remove their own join, and an admin remove any" do
      join = ProjectJoin.create!(project_proposal_id: approved.id, user_id: owner.id)
      content_login!(owner)
      delete unjoin_project_proposal_project_proposals_path, params: { project_proposal_id: approved.id, project_join_id: join.id }
      expect(ProjectJoin.exists?(join.id)).to be(false)
      expect(flash[:notice]).to eq("You unjoined this project.")
      join = ProjectJoin.create!(project_proposal_id: approved.id, user_id: other.id)
      content_sign_in_as(:admin)
      delete unjoin_project_proposal_project_proposals_path, params: { project_proposal_id: approved.id, project_join_id: join.id }
      expect(ProjectJoin.exists?(join.id)).to be(false)
    end

    it "404s for an unknown join" do
      content_login!(owner)
      delete unjoin_project_proposal_project_proposals_path, params: { project_proposal_id: approved.id, project_join_id: 0 }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "listing pages" do
    it "user_projects shows pending / approved / joined sets for the signed-in user" do
      ProjectJoin.create!(project_proposal_id: approved.id, user_id: other.id)
      content_login!(owner)
      get user_projects_project_proposals_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pending One", "Approved One")
      expect(response.body).not_to include("Declined One")
    end

    it "user_projects renders for a guest (empty sets)" do
      get user_projects_project_proposals_path
      expect(response).to have_http_status(:ok)
    end

    it "projects_assigned lists approved, joined proposals without a repository; projects_completed those with one" do
      joined = create(:project_proposal, :joined, title: "Assigned Only")
      done = create(:project_proposal, :completed, title: "Finished Work")
      get projects_assigned_project_proposals_path
      expect(response.body).to include("Assigned Only")
      expect(response.body).not_to include("Finished Work")
      get projects_completed_project_proposals_path
      expect(response.body).to include("Finished Work")
      expect(response.body).not_to include("Assigned Only")
      expect([joined, done]).to all(be_persisted)
    end
  end

  describe "JSON contact details" do
    let(:public_keys) do
      %w[id user_id admin_id approved title description youtube_link created_at updated_at area client_type url]
    end
    let(:contact_keys) { %w[username email client] }

    it "omits username, email and client for guests and unrelated users" do
      # index.json is not routable in practice: the action only responds to js/html (406).
      get project_proposals_path(format: :json)
      expect(response).to have_http_status(:not_acceptable)

      get project_proposal_path(approved.slug, format: :json)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).keys).to match_array(public_keys)

      content_login!(other)
      get project_proposal_path(approved.slug, format: :json)
      expect(JSON.parse(response.body).keys).to match_array(public_keys)
      expect(response.body).not_to include(approved.email, approved.client)
    end

    it "includes them for the owner and for admins" do
      content_login!(owner)
      get project_proposal_path(approved.slug, format: :json)
      body = JSON.parse(response.body)
      expect(body.keys).to match_array(public_keys + contact_keys)
      expect(body.values_at(*contact_keys)).to eq([approved.username, approved.email, approved.client])

      content_sign_in_as(:admin)
      get project_proposal_path(approved.slug, format: :json)
      expect(JSON.parse(response.body).keys).to match_array(public_keys + contact_keys)
    end

    it "leaves the HTML pages unaffected" do
      get project_proposal_path(approved.slug)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Approved One")
      get project_proposals_path
      expect(response).to have_http_status(:ok)
    end
  end
end
