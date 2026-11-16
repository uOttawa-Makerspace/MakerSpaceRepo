require "rails_helper"

RSpec.describe Staff::ProficientProjectSessionsController, type: :controller do
  describe "#show" do
    context "show" do
      it "should not allow regular user to access proficient project session" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        proficient_project_session = create(:proficient_project_session, level: "Beginner")
        get :show, params: { id: proficient_project_session.id }
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq("You cannot access this area.")
      end

      it "should allow admin to access proficient project session they approved" do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10_000
        proficient_project_session = create(:proficient_project_session, level: "Beginner")
        expect(get(:show, params: { id: proficient_project_session.id })).to have_http_status(:success)
      end

      it "should allow admin to access proficient project session they did not approve" do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10_000
        proficient_project_session = create(:proficient_project_session, level: "Beginner")
        expect(get(:show, params: { id: proficient_project_session.id })).to have_http_status(:success)
      end

      it "should allow staff member to access proficient project session they approved" do
        staff = create(:user, :staff)
        session[:user_id] = staff.id
        session[:expires_at] = Time.zone.now + 10_000
        proficient_project_session = create(:proficient_project_session, level: "Beginner", user: staff)
        expect(get(:show, params: { id: proficient_project_session.id })).to have_http_status(:success)
      end
    end

    context "sort arrows" do
      render_views

      it "gives each column header the arrow that sorts that column" do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10_000
        proficient_project_session = create(:proficient_project_session, level: "Beginner")
        get :show, params: { id: proficient_project_session.id }
        columns = response.body.scan(/sortTable\('training-session-users-table', (\d+)\)/).flatten.map(&:to_i)
        expect(columns).to eq([0, 1, 2, 3, 4])
      end
    end
  end

end