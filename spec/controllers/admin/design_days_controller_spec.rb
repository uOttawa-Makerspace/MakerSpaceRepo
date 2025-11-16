require "rails_helper"

RSpec.describe Admin::DesignDaysController, type: :controller do
  before(:each) { session[:user_id] = create(:user, :admin).id }

  # singular resource, no index
  describe "GET /show" do
    context "logged in as admin" do
      it "should return success" do
        get :show
        expect(response).to have_http_status(:success)
      end
    end

    context "logged as regular user" do
      it "should prevent access" do
        session[:user_id] = create(:user).id
        get :show
        expect(response).not_to have_http_status(:success)
      end
    end
  end

  describe "PATCH #update" do
    before(:each) { @design_day_params = attributes_for(:design_day) }

    context "as a regular user" do
      before(:each) { session[:user_id] = create(:user).id }
      it "should prevent access" do
        patch :update, params: { design_day: @design_day_params }, as: :json
        expect(response).not_to redirect_to DesignDay.instance
        expect(response).to redirect_to root_path
      end
    end

    context "as admin" do
      it "should update data to display" do
        patch :update, params: { design_day: @design_day_params }, as: :json
        # only one design day here
        expect(response).to redirect_to DesignDay.instance
        expect(
          DesignDay.instance.attributes.symbolize_keys.except(:id)
        ).to include @design_day_params
      end
    end
  end

  describe "design day usage" do
    before(:each) { session[:user_id] = create(:user).id }

    context "in the design day website display" do
      it "should be a full json" do
        create :design_day
        get :data
        expect(response).to have_http_status :success
        scheds = JSON.parse(response.body, symbolize_names: true)

        # making sure the names don't randomly change one day
        %i[
          day
          sheet_key
          is_live
          design_day_schedules
          semester
          year
          design_day_schedules
          show_floorplans
          floorplan_urls
        ].each { |k| expect(scheds).to have_key(k) }

        scheds[:design_day_schedules].each do |dds|
          expect(%w[student judge]).to include(dds[:event_for])
        end

        test_sched = scheds[:design_day_schedules].first
        %i[start end ordering title_en title_fr event_for].each do |k|
          expect(test_sched).to have_key(k)
        end

        expect(scheds[:floorplan_urls]).not_to be_blank
      end
    end
  end
end
