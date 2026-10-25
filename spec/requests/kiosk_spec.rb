require "rails_helper"

# Chunk 15: KioskController. A kiosk is a browser left logged in as a staff
# or admin user; there is no device token. Everything is gated by
# `current_user.staff? || current_user.admin?`; guests and regular users are
# bounced to root with "You cannot access this area.". Once in, the kiosk lets
# the session holder sign ANY user (looked up by username or email, no password)
# in or out of any space.
RSpec.describe "Kiosks", type: :request do
  let!(:space) { create(:space) }
  let(:visitor) { create(:user, :regular_user) }

  def expect_bounced
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq("You cannot access this area.")
  end

  describe "auth matrix" do
    {
      "GET /kiosk" => -> { get kiosk_index_path },
      "GET /kiosk/:id" => -> { get kiosk_path(space.id) },
      "GET /kiosk/:id/edit" => -> { get edit_kiosk_path(space.id) },
      "POST /kiosk/:id/sign_email" => -> { post kiosk_sign_email_path(space.id), params: { visitor: visitor.username, entering: "true" } }
    }.each do |label, action|
      %i[guest regular volunteer].each do |role|
        it "#{label} bounces a #{role}" do
          sign_in_as(role)
          instance_exec(&action)
          expect_bounced
        end
      end
    end

    it "does not create a lab session for a guest posting sign_email" do
      expect { post kiosk_sign_email_path(space.id), params: { visitor: visitor.username, entering: "true" } }.not_to change(LabSession, :count)
    end

    %i[staff admin].each do |role|
      it "lets #{role} open index, show and edit" do
        sign_in_as(role)
        get kiosk_index_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(space.name)
        get kiosk_path(space.id)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Welcome to #{space.name}")
        expect(response.body).to include(kiosk_sign_email_path(space.id))
        get edit_kiosk_path(space.id)
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "GET /kiosk/:id" do
    it "redirects to the kiosk index for an unknown space" do
      sign_in_as(:staff)
      get kiosk_path(0)
      expect(response).to redirect_to(kiosk_index_path)
    end

    it "renders without a layout (full html document of its own)" do
      sign_in_as(:staff)
      get kiosk_path(space.id)
      expect(response.body).to include("<title>#{space.name} Kiosk</title>")
      expect(response.body).not_to include("navbar-expand-xl")
    end
  end

  describe "POST /kiosk/:id/sign_email" do
    before { sign_in_as(:staff) }

    it "signs a visitor in by username with an 8 hour session and redirects to the kiosk" do
      expect { post kiosk_sign_email_path(space.id), params: { visitor: visitor.username, entering: "true" } }.to change(LabSession, :count).by(1)
      expect(response).to redirect_to(kiosk_path(space.id))
      expect(flash[:notice]).to eq("Signing in to #{space.name}, hello #{visitor.name}")
      ls = LabSession.last
      expect(ls).to have_attributes(user_id: visitor.id, space_id: space.id)
      expect(ls.sign_out_time - ls.sign_in_time).to be_within(5.seconds).of(8.hours)
    end

    it "signs a visitor in by email" do
      post kiosk_sign_email_path(space.id), params: { visitor: visitor.email, entering: "true" }
      expect(LabSession.last.user_id).to eq(visitor.id)
    end

    it "does not create a second session while one is active, but still flashes a welcome" do
      post kiosk_sign_email_path(space.id), params: { visitor: visitor.username, entering: "true" }
      expect { post kiosk_sign_email_path(space.id), params: { visitor: visitor.username, entering: "true" } }.not_to change(LabSession, :count)
      expect(flash[:notice]).to eq("Signing in to #{space.name}, hello #{visitor.name}")
    end

    it "signs a visitor out by ending the active session now" do
      post kiosk_sign_email_path(space.id), params: { visitor: visitor.username, entering: "true" }
      post kiosk_sign_email_path(space.id), params: { visitor: visitor.username, leaving: "true" }
      expect(response).to redirect_to(kiosk_path(space.id))
      expect(flash[:notice]).to eq("Signing out from #{space.name}, bye #{visitor.name}")
      expect(LabSession.where(user: visitor).active).to be_empty
    end

    it "flashes a sign-out notice even when there was nothing to end" do
      expect { post kiosk_sign_email_path(space.id), params: { visitor: visitor.username, leaving: "true" } }.not_to change(LabSession, :count)
      expect(flash[:notice]).to eq("Signing out from #{space.name}, bye #{visitor.name}")
    end

    it "does nothing and redirects back with a notice-less flash when neither entering nor leaving is sent" do
      expect { post kiosk_sign_email_path(space.id), params: { visitor: visitor.username } }.not_to change(LabSession, :count)
      expect(response).to redirect_to(kiosk_path(space.id))
      expect(flash[:notice]).to be_nil
    end

    it "alerts for an unknown visitor" do
      post kiosk_sign_email_path(space.id), params: { visitor: "nobody-here", entering: "true" }
      expect(response).to redirect_to(kiosk_path(space.id))
      expect(flash[:alert]).to eq("User not found")
    end

    # WART(D-EQ06): sign_email calls `head :unprocessable_content` for an unknown space but does not return, so the later redirect_to raises DoubleRenderError (500)
    it "answers 500 (double render) and creates nothing for an unknown space" do
      expect { post kiosk_sign_email_path(0), params: { visitor: visitor.username, entering: "true" } }.not_to change(LabSession, :count)
      expect(response).to have_http_status(:internal_server_error)
    end

    # WART(D-EQ07): kiosk sign-in needs no password or token for the visitor: any staff session can sign any user (even admins) into a space by username
    it "signs an admin in by username without any credential check" do
      admin = create(:user, :admin)
      post kiosk_sign_email_path(space.id), params: { visitor: admin.username, entering: "true" }
      expect(LabSession.where(user: admin).active.count).to eq(1)
    end
  end
end
