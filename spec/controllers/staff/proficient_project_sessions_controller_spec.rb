require "rails_helper"

RSpec.describe Staff::ProficientProjectSessionsController, type: :controller do
  describe "#show" do
    context "show" do
      it "should not allow regular user to access proficient project session" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        proficient_project_session = create(:proficient_project_session, level: "Beginner")
        get :show, params: { id: ProficientProjectSession.last.id }
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq("You cannot access this area.")
      end

      it "should allow admin to access proficient project session they approved" do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10_000
        proficient_project_session = create(:proficient_project_session, level: "Beginner")
        expect(get(:show, params: { id: ProficientProjectSession.last.id })).to have_http_status(:success)
      end

      it "should allow admin to access proficient project session they did not approve" do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10_000
        proficient_project_session = create(:proficient_project_session, level: "Beginner")
        expect(get(:show, params: { id: ProficientProjectSession.last.id })).to have_http_status(:success)
      end

      it "should allow staff member to access proficient project session they approved" do
        staff = create(:user, :staff)
        session[:user_id] = staff.id
        session[:expires_at] = Time.zone.now + 10_000
        proficient_project_session = create(:proficient_project_session, level: "Beginner", user: staff)
        get(:show, params: { id: ProficientProjectSession.last.id })
        expect(get(:show, params: { id: ProficientProjectSession.last.id })).to have_http_status(:success)
      end
    end
  end

end