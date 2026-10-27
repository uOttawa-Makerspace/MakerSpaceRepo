# frozen_string_literal: true

require "rails_helper"

# Chunk 17: announcements (staff + admin), dismiss, faqs, help centre form,
# getting started, quick access links, settings, changelog, template partials.
#
# Gate summary (verified in the controllers):
#   AnnouncementsController   < StaffAreaController   ensure_staff except dismiss
#   Admin::AnnouncementsController < AdminAreaController   ensure_admin
#   FaqsController            index public; everything else ensure_admin -> redirect "/"
#   HelpController, GettingStartedController, TemplateController: public
#   QuickAccessLinksController: check_user (admin only, see WARTs)
#   SettingsController: signed_in only (any role)
# Guests get current_user = User.new (never nil).
RSpec.describe "Content pages (part 2)", type: :request do
  def login_redirect?(path)
    expect(response).to have_http_status(:found)
    expect(CGI.unescape(response.location)).to include("/login?back_to=#{path}")
  end

  # ------------------------------------------------------------------
  describe "AnnouncementsController (staff area, volunteer announcements)" do
    let(:admin) { create(:user, :admin) }
    let!(:volunteer_ann) { create(:announcement, :volunteer, user: admin, description: "Vol news") }
    let!(:admin_ann) { create(:announcement, :admin, user: admin, description: "Admins only news") }

    it "sends a guest to login for every staff action" do
      [
        -> { get announcements_path }, -> { get new_announcement_path },
        -> { get announcement_path(volunteer_ann) }, -> { get edit_announcement_path(volunteer_ann) },
        -> { post announcements_path, params: { announcement: { description: "x", public_goal: "volunteer" } } },
        -> { patch announcement_path(volunteer_ann), params: { announcement: { description: "x" } } },
        -> { delete announcement_path(volunteer_ann) }
      ].each do |call|
        instance_exec(&call)
        expect(response).to have_http_status(:found)
        expect(response.location).to include("/login")
      end
      expect(Announcement.count).to eq(2)
      expect(volunteer_ann.reload.description).to eq("Vol news")
    end

    it "bounces a regular user to root with an alert" do
      sign_in_as(:regular)
      get announcements_path
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You cannot access this area.")
      expect { delete announcement_path(volunteer_ann) }.not_to change(Announcement, :count)
    end

    it "lets staff list only volunteer announcements" do
      sign_in_as(:staff)
      get announcements_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Vol news")
      expect(response.body).not_to include("Admins only news")
    end

    it "lets staff create a volunteer announcement owned by them" do
      staff = sign_in_as(:staff)
      expect {
        post announcements_path, params: { announcement: { description: "Hello", public_goal: "volunteer", active: true } }
      }.to change(Announcement, :count).by(1)
      expect(response).to redirect_to(announcements_path)
      expect(flash[:notice]).to eq("You've successfully created an announcement for Volunteer")
      expect(Announcement.last).to have_attributes(user_id: staff.id, public_goal: "volunteer", description: "Hello")
    end

    it "stops staff creating a non-volunteer announcement" do
      sign_in_as(:staff)
      expect {
        post announcements_path, params: { announcement: { description: "Hello", public_goal: "all" } }
      }.not_to change(Announcement, :count)
      expect(response).to redirect_to(new_announcement_path)
      expect(flash[:alert]).to eq("Please select another public goal")
    end

    it "lets an admin create any audience through the staff controller" do
      sign_in_as(:admin)
      expect {
        post announcements_path, params: { announcement: { description: "Hi all", public_goal: "all" } }
      }.to change(Announcement.all_users, :count).by(1)
    end

    # WART(D-P07): staff may re-target a volunteer announcement to any audience on update; only the stored goal is checked, not the submitted one
    it "lets staff escalate a volunteer announcement to 'all' (every visitor) via update" do
      sign_in_as(:staff)
      patch announcement_path(volunteer_ann), params: { announcement: { public_goal: "all" } }
      expect(response).to redirect_to(announcements_path)
      expect(flash[:notice]).to eq("Announcement updated")
      expect(volunteer_ann.reload.public_goal).to eq("all")
    end

    it "blocks staff from updating or deleting an admin announcement" do
      sign_in_as(:staff)
      patch announcement_path(admin_ann), params: { announcement: { description: "hacked" } }
      expect(response).to redirect_to(new_announcement_path)
      expect(admin_ann.reload.description).to eq("Admins only news")
      expect { delete announcement_path(admin_ann) }.not_to change(Announcement, :count)
    end

    # WART(D-P08): staff can open the show/edit pages of ANY announcement (even admin-only) because set_announcement has no audience check; only update/destroy are guarded
    it "lets staff read and open the edit form of an admin-only announcement" do
      sign_in_as(:staff)
      get announcement_path(admin_ann)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Admins only news")
      get edit_announcement_path(admin_ann)
      expect(response).to have_http_status(:ok)
    end

    it "lets staff delete a volunteer announcement" do
      sign_in_as(:staff)
      expect { delete announcement_path(volunteer_ann) }.to change(Announcement, :count).by(-1)
      expect(response).to redirect_to(announcements_path)
      expect(flash[:notice]).to eq("Announcement Deleted")
    end

    it "lets an admin update and delete an admin announcement via the staff controller" do
      sign_in_as(:admin)
      patch announcement_path(admin_ann), params: { announcement: { description: "edited" } }
      expect(admin_ann.reload.description).to eq("edited")
      expect { delete announcement_path(admin_ann) }.to change(Announcement, :count).by(-1)
    end

    it "404s for an unknown announcement id (show)" do
      sign_in_as(:staff)
      get announcement_path(id: 0)
      expect(response).to have_http_status(:not_found)
    end

    it "renders the new form for staff" do
      sign_in_as(:staff)
      get new_announcement_path
      expect(response).to have_http_status(:ok)
    end
  end

  # ------------------------------------------------------------------
  describe "Admin::AnnouncementsController" do
    let(:admin) { create(:user, :admin) }
    let!(:ann) { create(:announcement, :staff, user: admin, description: "Staff news") }

    it "redirects guests, regular users and staff to root" do
      %i[guest regular staff].each do |role|
        sign_in_as(role)
        get admin_announcements_path
        expect(response).to redirect_to("/"), role.to_s
        expect { delete admin_announcement_path(ann) }.not_to change(Announcement, :count)
        patch admin_announcement_path(ann), params: { announcement: { description: "x" } }
        expect(ann.reload.description).to eq("Staff news")
        post admin_announcements_path, params: { announcement: { description: "x", public_goal: "all" } }
        expect(Announcement.count).to eq(1)
        post logout_path
      end
    end

    # N+1 pinned: see defects D-PERF-P02
    it "lists all announcements for an admin", skip_bullet: true do
      create(:announcement, :volunteer, user: admin, description: "Vol news")
      sign_in_as(:admin)
      get admin_announcements_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Staff news", "Vol news")
      get new_admin_announcement_path
      expect(response).to have_http_status(:ok)
      get admin_announcement_path(ann)
      expect(response).to have_http_status(:ok)
      get edit_admin_announcement_path(ann)
      expect(response).to have_http_status(:ok)
    end

    it "creates an announcement for any audience string" do
      admin = sign_in_as(:admin)
      post admin_announcements_path, params: { announcement: { description: "Hello", public_goal: "all", active: true, end_date: "2030-01-01" } }
      expect(response).to redirect_to(admin_announcements_path)
      expect(flash[:notice]).to eq("You've successfully created an announcement for All")
      expect(Announcement.last).to have_attributes(user_id: admin.id, public_goal: "all", active: true, end_date: Date.new(2030, 1, 1))
    end

    # WART(D-P09): public_goal is not validated, so an admin can save an audience nothing ever displays (e.g. "regular_user", a typo, or even blank)
    it "accepts a typo'd or blank public_goal" do
      sign_in_as(:admin)
      expect {
        post admin_announcements_path, params: { announcement: { description: "Typo", public_goal: "evryone" } }
      }.to change(Announcement, :count).by(1)
      expect(flash[:notice]).to eq("You've successfully created an announcement for Evryone")
      expect {
        post admin_announcements_path, params: { announcement: { description: "Blank" } }
      }.to change(Announcement, :count).by(1) # saved, then the flash line raises on nil.capitalize
      expect(response).to have_http_status(:internal_server_error)
      expect(Announcement.last.public_goal).to be_nil
    end

    it "requires the announcement param" do
      sign_in_as(:admin)
      post admin_announcements_path, params: {}
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to match(/announcement/)
    end

    it "updates and deletes" do
      sign_in_as(:admin)
      patch admin_announcement_path(ann), params: { announcement: { description: "edited", active: false } }
      expect(response).to redirect_to(admin_announcements_path)
      expect(flash[:notice]).to eq("Announcement updated")
      expect(ann.reload).to have_attributes(description: "edited", active: false)
      expect { delete admin_announcement_path(ann) }.to change(Announcement, :count).by(-1)
      expect(flash[:notice]).to eq("Announcement Deleted")
    end

    it "destroys the dismissal rows with the announcement" do
      reader = create(:user, :regular_user)
      AnnouncementDismiss.create!(user: reader, announcement: ann)
      sign_in_as(:admin)
      expect { delete admin_announcement_path(ann) }.to change(AnnouncementDismiss, :count).by(-1)
    end
  end

  # ------------------------------------------------------------------
  describe "announcement visibility on the homepage and dismiss persistence" do
    let(:admin) { create(:user, :admin) }

    def ann!(goal, text, **attrs)
      create(:announcement, user: admin, public_goal: goal, description: text, **attrs)
    end

    it "shows 'all' announcements to a guest (as 'To All Visitors') but nothing role-specific" do
      ann!("all", "Everyone news")
      ann!("staff", "Staff-only news")
      ann!("admin", "Admin-only news")
      ann!("volunteer", "Volunteer-only news")
      get root_path
      expect(response.body).to include("To All Visitors", "Everyone news")
      expect(response.body).not_to include("Staff-only news", "Admin-only news", "Volunteer-only news")
    end

    it "hides inactive and expired announcements, shows ones expiring today or never" do
      ann!("all", "Inactive news", active: false)
      ann!("all", "Expired news", end_date: Date.yesterday)
      ann!("all", "Ends today news", end_date: Time.zone.today)
      ann!("all", "Open-ended news", end_date: nil)
      get root_path
      expect(response.body).to include("Ends today news", "Open-ended news")
      expect(response.body).not_to include("Inactive news", "Expired news")
    end

    it "shows each audience block to the right role" do
      ann!("staff", "Staff-only news")
      ann!("admin", "Admin-only news")
      ann!("volunteer", "Volunteer-only news")

      sign_in_as(:regular)
      get root_path
      expect(response.body).not_to include("Staff-only news", "Admin-only news", "Volunteer-only news")
      post logout_path

      sign_in_as(:staff)
      get root_path
      expect(response.body).to include("Staff-only news", "Volunteer-only news")
      expect(response.body).not_to include("Admin-only news")
      post logout_path

      sign_in_as(:admin)
      get root_path
      expect(response.body).to include("Admin-only news")
      post logout_path

      vol = create(:user, :regular_user)
      vol.programs.create!(program_type: Program::VOLUNTEER)
      log_in!(vol)
      get root_path
      expect(response.body).to include("Volunteer-only news")
      expect(response.body).not_to include("Staff-only news")
    end

    # WART(D-P10): 'regular_user' announcements are never displayed to anyone (the partial only checks that one exists, then renders the 'all' ones a second time)
    it "never shows regular_user announcements and renders 'all' twice for signed-in users when one exists" do
      ann!("regular_user", "Regular-only news")
      ann!("all", "Everyone news")
      sign_in_as(:regular)
      get root_path
      expect(response.body).not_to include("Regular-only news")
      expect(response.body.scan("Everyone news").size).to eq(2)
      expect(response.body).to include("To All Users", "To All Visitors")
    end

    it "renders announcement text escaped (no markup injection)" do
      ann!("all", "<script>alert(1)</script><b>bold</b>")
      get root_path
      expect(response.body).not_to include("<script>alert(1)</script>")
      expect(response.body).to include("&lt;script&gt;alert(1)&lt;/script&gt;")
    end

    describe "PUT /announcements/dismiss" do
      let!(:news) { ann!("all", "Everyone news") }

      it "persists a dismissal for a signed-in user and hides it for them only" do
        user = sign_in_as(:regular)
        other = create(:user, :regular_user)
        expect {
          put dismiss_announcements_path(announcement_id: news.id)
        }.to change { AnnouncementDismiss.where(user: user, announcement: news).count }.from(0).to(1)
        expect(response).to have_http_status(:no_content)
        get root_path
        expect(response.body).not_to include("Everyone news")
        post logout_path
        sign_in_as(:regular) # a different user still sees it
        get root_path
        expect(response.body).to include("Everyone news")
        expect(other).to be_present
      end

      it "is not guarded: a guest request answers 204 but persists nothing" do
        expect {
          put dismiss_announcements_path(announcement_id: news.id)
        }.not_to change(AnnouncementDismiss, :count)
        expect(response).to have_http_status(:no_content)
      end

      it "silently ignores an unknown announcement id" do
        sign_in_as(:regular)
        expect {
          put dismiss_announcements_path(announcement_id: 0)
        }.not_to change(AnnouncementDismiss, :count)
        expect(response).to have_http_status(:no_content)
      end

      # WART(D-P11): no uniqueness on (user, announcement), so repeated dismisses pile up duplicate rows
      it "creates a duplicate row on a repeated dismiss" do
        user = sign_in_as(:regular)
        2.times { put dismiss_announcements_path(announcement_id: news.id) }
        expect(AnnouncementDismiss.where(user: user, announcement: news).count).to eq(2)
      end

      it "dismissal survives the expiry window: an expired announcement stays hidden, a re-activated one stays dismissed" do
        user = sign_in_as(:regular)
        put dismiss_announcements_path(announcement_id: news.id)
        news.update!(active: false)
        news.update!(active: true)
        get root_path
        expect(response.body).not_to include("Everyone news")
        expect(AnnouncementDismiss.where(user: user).count).to eq(1)
      end
    end
  end

  # ------------------------------------------------------------------
  describe "FaqsController" do
    let!(:faq1) { create(:faq, title_en: "First?", body_en: "<b>Bold</b><script>x()</script>", order: 1) }
    let!(:faq2) { create(:faq, title_en: "Second?", order: 2) }
    let(:valid_params) { { faq: { title_en: "T en", title_fr: "T fr", body_en: "B en", body_fr: "B fr" } } }

    it "lists FAQs publicly in order and sanitizes the body" do
      get faqs_path
      expect(response).to have_http_status(:ok)
      expect(response.body.index("First?")).to be < response.body.index("Second?")
      expect(response.body).to include("<b>Bold</b>")
      expect(response.body).not_to include("<script>x()</script>")
      expect(response.body).not_to include("New Entry")
    end

    it "shows the French title for the fr locale" do
      faq1.update!(title_fr: "Premier ?")
      get faqs_path(locale: "fr")
      expect(response.body).to include("Premier ?")
    end

    it "shows admin controls to an admin only" do
      sign_in_as(:admin)
      get faqs_path
      expect(response.body).to include("New Entry", edit_faq_path(faq1))
    end

    it "redirects non-admins (guest, regular, staff) to root for every write action" do
      %i[guest regular staff].each do |role|
        sign_in_as(role)
        [
          -> { get new_faq_path }, -> { get edit_faq_path(faq1) },
          -> { post faqs_path, params: valid_params },
          -> { patch faq_path(faq1), params: { faq: { title_en: "hacked" } } },
          -> { delete faq_path(faq1) },
          -> { put reorder_faqs_path, params: { data: [faq2.id, faq1.id] }, as: :json }
        ].each do |call|
          instance_exec(&call)
          expect(response).to redirect_to("/"), role.to_s
        end
        expect(Faq.count).to eq(2)
        expect(faq1.reload.title_en).to eq("First?")
        expect(faq1.order).to eq(1)
        post logout_path
      end
    end

    it "lets an admin create (renders a fresh form, 200), update, and delete" do
      sign_in_as(:admin)
      expect { post faqs_path, params: valid_params }.to change(Faq, :count).by(1)
      expect(response).to have_http_status(:ok)
      expect(flash[:notice]).to eq("Created FAQ successfully")

      patch faq_path(faq1), params: { faq: { title_en: "Edited" } }
      expect(response).to redirect_to(faqs_path)
      expect(faq1.reload.title_en).to eq("Edited")

      expect { delete faq_path(faq1) }.to change(Faq, :count).by(-1)
      expect(response).to redirect_to(faqs_path)
    end

    # WART(D-P12): the failed-create flash says "Created FAQ successfully"
    it "rejects an invalid create with 422 but a success-sounding alert" do
      sign_in_as(:admin)
      expect { post faqs_path, params: { faq: { title_en: "only title" } } }.not_to change(Faq, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to eq("Created FAQ successfully")
    end

    it "rejects an invalid update with 422" do
      sign_in_as(:admin)
      patch faq_path(faq1), params: { faq: { title_en: "" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to eq("Failed to update entry")
      expect(faq1.reload.title_en).to eq("First?")
    end

    it "reorders by the submitted id list, appending unmentioned FAQs" do
      faq3 = create(:faq, order: 3)
      sign_in_as(:admin)
      put reorder_faqs_path, params: { data: [faq3.id, faq1.id] }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("ping")
      expect(Faq.unscoped.order(:order).pluck(:id)).to eq([faq3.id, faq1.id, faq2.id])
    end

    it "is a no-op with empty data and 500s/404s for an unknown id" do
      sign_in_as(:admin)
      put reorder_faqs_path, params: {}, as: :json
      expect(response).to have_http_status(:ok)
      put reorder_faqs_path, params: { data: [0, faq1.id] }, as: :json
      expect(response).to have_http_status(:not_found)
      expect(faq1.reload.order).to eq(1)
    end

    it "404s for an unknown id on edit" do
      sign_in_as(:admin)
      get edit_faq_path(id: 0)
      expect(response).to have_http_status(:not_found)
    end
  end

  # ------------------------------------------------------------------
  describe "HelpController (support form)" do
    let(:comments) { "I cannot book the laser cutter room" }
    let(:params) do
      { help: { name: "Pat Visitor", email: "pat@example.test", subject: "Booking does not work", comments: comments } }
    end

    it "renders the form for guests and users" do
      get help_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="help[subject]"', 'name="help[comments]"')
      sign_in_as(:regular)
      get help_path
      expect(response).to have_http_status(:ok)
    end

    it "submits as a guest: persisted, redirected, and the issue email is delivered to the SUBMITTED address with a support bcc" do
      deliveries.clear
      expect {
        perform_enqueued_jobs { post help_path, params: params }
      }.to change(Help, :count).by(1)
      expect(response).to redirect_to(help_path)
      expect(flash[:notice]).to eq("Your issue has been submitted.")
      expect(Help.last.gh_issue_number.to_s).to eq("111")
      expect(deliveries.size).to eq(1)
      mail = deliveries.last
      expect(mail.to).to eq(["pat@example.test"])
      expect(mail.bcc).to eq(["uottawa.makerepo@gmail.com"])
      expect(mail.subject).to eq("Issue Report | Booking does not work")
      expect(mail.body.encoded).to include(comments)
    end

    # WART(D-P13): any guest can make the app email arbitrary text to any address (recipient, subject and body are all form fields); only the captcha stands in the way
    it "emails an arbitrary third-party recipient with attacker-chosen content" do
      deliveries.clear
      victim = { help: params[:help].merge(email: "victim@example.test", subject: "Your account is compromised, click here", comments: "http://evil.example.test") }
      perform_enqueued_jobs { post help_path, params: victim }
      expect(deliveries.last.to).to eq(["victim@example.test"])
      expect(deliveries.last.body.encoded).to include("http://evil.example.test")
    end

    it "rejects invalid input with 422 and sends nothing" do
      deliveries.clear
      bad = { help: { name: "P", email: "not-an-email", subject: "short", comments: "" } }
      expect {
        perform_enqueued_jobs { post help_path, params: bad }
      }.not_to change(Help, :count)
      expect(response).to have_http_status(422)
      expect(flash[:alert]).to eq("An error occurred while receiving your issue.")
      expect(deliveries).to be_empty
    end

    it "400s/redirects when the help param is missing" do
      post help_path, params: {}
      expect(response).to redirect_to(root_path)
    end

    it "fails the submission (422, nothing sent) when GitHub issue creation returns no number" do
      allow_any_instance_of(GithubIssuesService).to receive(:create_issue).and_return({ number: nil })
      deliveries.clear
      expect {
        perform_enqueued_jobs { post help_path, params: params }
      }.not_to change(Help, :count)
      expect(response).to have_http_status(422)
      expect(deliveries).to be_empty
    end
  end

  # ------------------------------------------------------------------
  describe "GettingStartedController" do
    it "serves both guides publicly" do
      get getting_started_sua_path
      expect(response).to have_http_status(:ok)
      get getting_started_cr_path
      expect(response).to have_http_status(:ok)
      sign_in_as(:regular)
      get getting_started_sua_path
      expect(response).to have_http_status(:ok)
    end
  end

  # ------------------------------------------------------------------
  describe "QuickAccessLinksController (admin only)" do
    let(:admin) { create(:user, :admin) }

    # WART(D-P14): check_user redirects twice in one filter chain (guest/regular + :id), which raises DoubleRenderError (500) instead of a clean redirect
    it "redirects a guest or regular user without an id (create)" do
      post quick_access_links_create_path, params: { name: "Home", path: "/" }
      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("You can't do that")
      expect(QuickAccessLink.count).to eq(0)
      sign_in_as(:regular)
      post quick_access_links_create_path, params: { name: "Home", path: "/" }
      expect(response).to redirect_to(root_path)
      expect(QuickAccessLink.count).to eq(0)
    end

    it "answers 500 (double redirect) when a non-admin supplies an id of an existing link" do
      link = QuickAccessLink.create!(user: admin, name: "Home", path: "/")
      sign_in_as(:regular)
      delete quick_access_links_delete_path(link)
      expect(response).to have_http_status(:internal_server_error)
      expect(QuickAccessLink.exists?(link.id)).to be(true)
    end

    it "lets an admin create, update, and delete their own link" do
      me = sign_in_as(:admin)
      post quick_access_links_create_path, params: { name: "Home", path: "/" }
      expect(response).to have_http_status(:no_content)
      link = QuickAccessLink.find_by!(user: me)
      expect(link).to have_attributes(name: "Home", path: "/")

      post quick_access_links_update_path(link), params: { name: "Faq", path: "/faq" }
      expect(response).to have_http_status(:no_content)
      expect(link.reload).to have_attributes(name: "Faq", path: "/faq")

      delete quick_access_links_delete_path(link), headers: { "HTTP_REFERER" => "http://www.example.com/faq" }
      expect(response).to redirect_to("http://www.example.com/faq")
      expect(QuickAccessLink.exists?(link.id)).to be(false)
    end

    it "deletes the link when an update is submitted with a blank name or path" do
      me = sign_in_as(:admin)
      link = QuickAccessLink.create!(user: me, name: "Home", path: "/")
      post quick_access_links_update_path(link), params: { name: "", path: "/" }
      expect(response).to redirect_to(user_path(me.username))
      expect(QuickAccessLink.exists?(link.id)).to be(false)
    end

    it "rejects invalid and duplicate paths with an alert redirect" do
      me = sign_in_as(:admin)
      post quick_access_links_create_path, params: { name: "Bad", path: "/no/such/route/at/all/xyz" }
      expect(response).to have_http_status(:found)
      expect(flash[:alert]).to start_with("Quick access link not created")
      post quick_access_links_create_path, params: { name: "Home", path: "/" }
      post quick_access_links_create_path, params: { name: "Home2", path: "/" }
      expect(flash[:alert]).to include("You already have a quick access link to that location")
      expect(QuickAccessLink.where(user: me).count).to eq(1)
    end

    it "does not let an admin touch another admin's link" do
      other = create(:user, :admin)
      link = QuickAccessLink.create!(user: other, name: "Home", path: "/")
      sign_in_as(:admin)
      delete quick_access_links_delete_path(link)
      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("You can't do that")
      expect(QuickAccessLink.exists?(link.id)).to be(true)
    end

    it "404s for an unknown link id as admin" do
      sign_in_as(:admin)
      delete quick_access_links_delete_path(id: 0)
      expect(response).to have_http_status(:not_found)
    end
  end

  # ------------------------------------------------------------------
  describe "SettingsController (own account settings)" do
    it "sends a guest to login for both pages" do
      get settings_profile_path
      login_redirect?("/settings/profile")
      get settings_admin_path
      login_redirect?("/settings/admin")
    end

    # WART(D-P15): /settings/admin is open to every signed-in role (it is the user's own password/GitHub page, but the name and the Admin::* family suggest an admin gate)
    it "serves both pages to any signed-in role, not just admins" do
      %i[regular staff admin].each do |role|
        sign_in_as(role)
        get settings_profile_path
        expect(response).to have_http_status(:ok), role.to_s
        get settings_admin_path
        expect(response).to have_http_status(:ok), role.to_s
        post logout_path
      end
    end
  end

  # ------------------------------------------------------------------
  describe "ChangelogController" do
    it "renders CHANGELOG.md as HTML for guests, without the #changelog marker" do
      get changelog_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<h1>")
      expect(response.body).not_to match(/^#changelog\s*$/)
    end

    it "shows a fallback when there is no changelog file" do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(Rails.root.join("CHANGELOG.md")).and_return(false)
      get changelog_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No changelog available.")
    end

    # WART(D-P16): changelog markdown is rendered without filter_html and marked html_safe, so raw HTML in CHANGELOG.md (written by the release tooling from PR titles) reaches visitors unescaped
    it "passes raw HTML in the markdown through unescaped" do
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(Rails.root.join("CHANGELOG.md")).and_return(+"# v1\n\n<script>window.x=1</script>\n")
      get changelog_path
      expect(response.body).to include("<script>window.x=1</script>")
    end
  end

  # ------------------------------------------------------------------
  describe "TemplateController (HTML fragments used by JS)" do
    it "renders layout-less fragments publicly and escapes params" do
      get template_category_path(category: "<img src=x onerror=1>")
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('<span class="category">&lt;img src=x onerror=1&gt;</span>')
      get template_equipment_path(equipment: "Laser")
      expect(response.body).to include('<span class="equipment">Laser</span>')
      get template_certification_path(certification: "Basic")
      expect(response.body).to include('<span class="certification">Basic</span>')
      get template_file_path(file: "plan.pdf", size: "12")
      expect(response.body).to include("plan.pdf", "12 KB")
      expect(response.body).not_to include("<html")
    end

    # WART(D-P17): the comment fragment calls vote_path, which no longer exists, so GET /template/comment always answers 500
    it "answers 500 for the comment fragment, with or without params (dead vote_path helper)" do
      get template_comment_path(comment_id: 5, username: "pat", rep: "3", content: "<b>ok</b>",
                                user_url: "http://example.test", created_at: 2.hours.ago.iso8601)
      expect(response).to have_http_status(:internal_server_error)
      get template_comment_path
      expect(response).to have_http_status(:internal_server_error)
    end
  end
end
