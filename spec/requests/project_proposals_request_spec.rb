# frozen_string_literal: true

require "rails_helper"

# Chunk 16: ProjectProposalsController (HTTP contract).
#
# The controller has NO signed_in / ownership / admin before_action. The only
# gates are inline: show (approved, or admin, or the owner), destroy
# (`return unless admin?`), and params[:season/:year] (admin only). Guests get
# current_user = User.new (never nil), so the `current_user.nil?` captcha branch
# in #create is dead code. Many "admin" actions are therefore open to anyone:
# see the severity-1 D-C rows.
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
    it "shows every proposal, pending and declined included, to a guest (D-C33)" do
      get project_proposals_path
      expect(response).to have_http_status(:ok)
      # WART(D-C33): index applies no approved filter, so unreviewed/declined proposals are public
      expect(response.body).to include("Approved One", "Pending One", "Declined One")
    end

    it "filters by status (1 approved, 0 declined, nil pending) and combinations" do
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
      create(:project_proposal, title: "Zebra Crossing")
      get project_proposals_path, params: { query: "zebra" }
      expect(response.body).to include("Zebra Crossing")
      expect(response.body).not_to include("Pending One", "Approved One")
      get project_proposals_path, params: { semester: "fall_2024" }
      expect(response.body).to include("Approved One")
      expect(response.body).not_to include("Pending One")
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

  describe "GET new / edit" do
    it "renders new for a guest" do
      get new_project_proposal_path
      expect(response).to have_http_status(:ok)
    end

    it "renders edit for a guest on someone else's proposal (D-C34, severity 1)" do
      get edit_project_proposal_path(pending.slug)
      # WART(D-C34): no auth/ownership on edit: any visitor can open any proposal's edit form (email, client details)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(pending.email)
    end
  end

  describe "POST create" do
    it "lets a guest create a proposal with no captcha check: the nil? guard never fires (D-C35)" do
      expect { post project_proposals_path, params: proposal_params }.to change(ProjectProposal, :count).by(1)
      # WART(D-C35): `current_user.nil? && !verify_turnstile` is dead (current_user is User.new); anonymous spam is unthrottled
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

    it "ignores spoofed approved/admin_id/user_id: a guest cannot self-approve (D-C36)" do
      post project_proposals_path, params: proposal_params(approved: "approved", admin_id: owner.id, user_id: other.id)
      pp = ProjectProposal.find_by(title: "New Idea")
      # FIXED(D-C36): :approved/:admin_id/:user_id are no longer permitted; only approve/decline set review fields
      expect(pp.approved).to be_nil
      expect(pp.admin_id).to be_nil
      expect(pp.user_id).to be_nil
    end

    it "a signed-in user cannot self-approve or spoof the owner on create (D-C36)" do
      content_login!(owner)
      post project_proposals_path, params: proposal_params(approved: "approved", admin_id: owner.id, user_id: other.id)
      expect(ProjectProposal.find_by(title: "New Idea")).to have_attributes(approved: nil, admin_id: nil, user_id: owner.id)
    end

    it "an admin cannot set review fields through create either (D-C36)" do
      content_sign_in_as(:admin)
      post project_proposals_path, params: proposal_params(approved: "approved", admin_id: owner.id)
      expect(ProjectProposal.find_by(title: "New Idea")).to have_attributes(approved: nil, admin_id: nil)
    end

    it "ignores approved sent as the numeric string '1' instead of 500ing (D-C36)" do
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

    it "attaches up to 5 images and any number of files of any type (D-C37)" do
      files = [content_pdf_upload, content_named_upload("run.exe", type: "application/x-msdownload")]
      imgs = Array.new(6) { content_png_upload }
      post project_proposals_path, params: { images: imgs, files: files }.merge(proposal_params)
      pp = ProjectProposal.find_by(title: "New Idea")
      expect(pp.photos.count).to eq(5)
      # WART(D-C37): project_files has no content-type or size validation
      expect(pp.project_files.map { |f| f.filename.to_s }).to contain_exactly("RepoFile1.pdf", "run.exe")
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
    it "lets a guest rewrite anyone's proposal, including approving it (D-C38, severity 1)" do
      patch project_proposal_path(pending.slug), params: { project_proposal: { title: "Hijacked", approved: "approved" } }
      # WART(D-C38): update has no auth or ownership check (the review fields are no longer permitted: FIXED(D-C36))
      pending.reload
      expect(pending.title).to eq("Hijacked")
      expect(pending.approved).to be_nil
      expect(response).to redirect_to(project_proposal_path(pending.slug))
      expect(flash[:notice]).to eq("Project proposal was successfully updated.")
    end

    it "the owner cannot reassign user_id or set review fields through mass assignment (D-C36)" do
      content_login!(owner)
      patch project_proposal_path(pending.slug),
            params: { project_proposal: { user_id: other.id, approved: "approved", admin_id: owner.id } }
      expect(pending.reload).to have_attributes(user_id: owner.id, approved: nil, admin_id: nil)
    end

    it "an admin cannot mass-assign review fields on update either (D-C36)" do
      content_sign_in_as(:admin)
      patch project_proposal_path(pending.slug), params: { project_proposal: { title: "Edited", approved: "approved", user_id: other.id } }
      expect(pending.reload).to have_attributes(title: "Edited", approved: nil, user_id: owner.id)
    end

    it "replaces categories, JSON answers with the uri" do
      Category.create!(name: "Old", project_proposal_id: pending.id)
      patch project_proposal_path(pending.slug, format: :json),
            params: { project_proposal: { title: "Retitled", categories: %w[New] } }
      expect(pending.reload.categories.pluck(:name)).to eq(["New"])
      expect(response.parsed_body).to eq("redirect_uri" => project_proposal_path(pending.slug))
    end

    it "wipes categories even when the update is invalid (D-C39)" do
      Category.create!(name: "Old", project_proposal_id: pending.id)
      patch project_proposal_path(pending.slug), params: { project_proposal: { title: "" } }
      expect(response).to have_http_status(:unprocessable_content)
      # WART(D-C39): categories.destroy_all runs before validation
      expect(pending.reload.categories).to be_empty
    end

    it "re-slugs to '<id>.<title>' on update" do
      patch project_proposal_path(pending.slug), params: { project_proposal: { title: "Zed Title" } }
      expect(pending.reload.slug).to eq("#{pending.id}.zed-title")
    end

    it "adds and deletes attachments (by filename or attachment id)" do
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
    it "does nothing for guests, owners and staff (action returns without rendering: 204) (D-C40)" do
      [nil, owner, create(:user, :staff)].each do |user|
        content_login!(user) if user
        expect { delete project_proposal_path(pending.slug) }.not_to change(ProjectProposal, :count)
        # WART(D-C40): `return unless admin?` renders nothing, so a refused delete answers 204 instead of a redirect/alert
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
    it "lets a guest approve and decline any proposal; admin_id ends nil (D-C41, severity 1)" do
      post approve_project_proposals_path, params: { id: pending.id }
      # WART(D-C41): approve/decline have no auth at all
      expect(pending.reload.approved).to eq("approved")
      expect(pending.admin_id).to be_nil
      expect(response).to redirect_to(project_proposals_url)
      expect(flash[:notice]).to eq("Project Proposal Approved")
      post decline_project_proposals_path, params: { id: approved.id }
      expect(approved.reload.approved).to eq("not_approved")
      expect(flash[:notice]).to eq("Project Proposal Declined")
    end

    it "records the signed-in reviewer as admin_id (staff and regular users too) and sends no email" do
      content_login!(other)
      ActionMailer::Base.deliveries.clear
      post approve_project_proposals_path, params: { id: pending.id }
      expect(pending.reload.admin_id).to eq(other.id)
      post decline_project_proposals_path, params: { id: pending.id }
      expect(pending.reload.approved).to eq("not_approved")
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "an admin approval is the same code path" do
      admin = content_sign_in_as(:admin)
      post approve_project_proposals_path, params: { id: pending.id }
      expect(pending.reload).to have_attributes(approved: "approved", admin_id: admin.id)
    end

    it "approve is not idempotent-guarded: re-approving a declined proposal flips it back, overwriting the reviewer" do
      post decline_project_proposals_path, params: { id: pending.id }
      post approve_project_proposals_path, params: { id: pending.id }
      expect(pending.reload.approved).to eq("approved")
    end

    it "404s for an unknown id" do
      post approve_project_proposals_path, params: { id: 0 }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST create_revision" do
    it "lets a guest clone ANY proposal (even a pending one) into a new pending 'Revision of ...' (D-C42, severity 1)" do
      expect { post create_revision_project_proposals_path, params: { old_project_proposal_id: pending.id } }
        .to change(ProjectProposal, :count).by(1)
      # WART(D-C42): no auth/ownership; copies another user's private proposal data into a new row
      rev = ProjectProposal.find_by(title: "Revision of Pending One")
      expect(rev.linked_project_proposal_id).to eq(pending.id)
      expect(rev.user_id).to be_nil
      expect(rev.approved).to be_nil
      expect(rev.admin_id).to be_nil
      expect(rev.email).to eq(pending.email)
      expect(response).to redirect_to(project_proposal_path(rev.slug))
      expect(flash[:notice]).to eq("The project proposal revision has been successfully created.")
    end

    it "sets the owner, copies photos, files (shared blobs) and categories, and sends NO email" do
      approved.photos.attach(io: File.open(Rails.root.join("spec/support/assets/avatar.png")), filename: "a.png", content_type: "image/png")
      approved.project_files.attach(io: File.open(Rails.root.join("spec/support/assets/RepoFile1.pdf")), filename: "f.pdf", content_type: "application/pdf")
      Category.create!(name: "cat", project_proposal_id: approved.id)
      content_login!(other)
      ActionMailer::Base.deliveries.clear
      post create_revision_project_proposals_path(format: :json), params: { old_project_proposal_id: approved.id }
      rev = ProjectProposal.find_by(linked_project_proposal_id: approved.id)
      expect(rev.user_id).to eq(other.id)
      expect(rev.photos.first.blob_id).to eq(approved.photos.first.blob_id)
      expect(rev.project_files.first.blob_id).to eq(approved.project_files.first.blob_id)
      expect(rev.categories.pluck(:name)).to eq(["cat"])
      expect(response.parsed_body).to eq("redirect_uri" => project_proposal_path(rev.slug))
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "does not carry over season/year/approval (a revision starts unreviewed)" do
      approved.update_columns(season: ProjectProposal.seasons[:fall], year: 2024)
      post create_revision_project_proposals_path, params: { old_project_proposal_id: approved.id }
      rev = ProjectProposal.find_by(linked_project_proposal_id: approved.id)
      expect(rev.attributes.values_at("season", "year", "approved")).to eq([nil, nil, nil])
    end

    it "redirects back with an alert for a missing or unknown id" do
      post create_revision_project_proposals_path
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to start_with("An error occured while trying to create")
      post create_revision_project_proposals_path, params: { old_project_proposal_id: 0 }
      expect(response).to redirect_to(root_path)
    end
  end

  describe "join / unjoin" do
    it "lets a guest join: a ProjectJoin with user_id nil (D-C43)" do
      expect { get join_project_proposal_project_proposals_path, params: { project_proposal_id: approved.id } }
        .to change(ProjectJoin, :count).by(1)
      # WART(D-C43): no signed_in; a guest join is stored with user_id nil
      expect(ProjectJoin.last.user_id).to be_nil
      expect(response).to redirect_to(project_proposal_path(approved.slug))
      expect(flash[:notice]).to eq("You joined this project.")
    end

    it "only one guest join fits per proposal: the nil user_id collides on the uniqueness scope" do
      2.times { get join_project_proposal_project_proposals_path, params: { project_proposal_id: approved.id } }
      expect(ProjectJoin.where(project_proposal_id: approved.id, user_id: nil).count).to eq(1)
      expect(flash[:alert]).to eq("You already joined this project or something went wrong.")
    end

    it "joins as the signed-in user, once; the second time alerts" do
      content_login!(other)
      expect { get join_project_proposal_project_proposals_path, params: { project_proposal_id: approved.id } }
        .to change { ProjectJoin.where(user_id: other.id).count }.by(1)
      expect { get join_project_proposal_project_proposals_path, params: { project_proposal_id: approved.id } }
        .not_to change(ProjectJoin, :count)
      expect(flash[:alert]).to eq("You already joined this project or something went wrong.")
    end

    it "can join an unapproved proposal (no approved check)" do
      content_login!(other)
      expect { get join_project_proposal_project_proposals_path, params: { project_proposal_id: pending.id } }
        .to change(ProjectJoin, :count).by(1)
    end

    it "lets anyone remove anyone else's join by id (D-C44, severity 1)" do
      join = ProjectJoin.create!(project_proposal_id: approved.id, user_id: owner.id)
      content_login!(other)
      get unjoin_project_proposal_project_proposals_path,
          params: { project_proposal_id: approved.id, project_join_id: join.id }
      # WART(D-C44): unjoin deletes by project_join_id with no ownership check (and not even scoped to the proposal)
      expect(ProjectJoin.exists?(join.id)).to be(false)
      expect(flash[:notice]).to eq("You unjoined this project.")
    end

    it "404s for an unknown join" do
      get unjoin_project_proposal_project_proposals_path, params: { project_proposal_id: approved.id, project_join_id: 0 }
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
end
