# frozen_string_literal: true

require "rails_helper"

# Admin::TimePeriodsController. Non-admins (guest included) are redirected to "/".

RSpec.describe "Admin time periods", type: :request do
  include SpacesSpecHelpers

  let!(:period) { TimePeriod.create!(name: "Fall", start_date: Date.new(2027, 9, 1), end_date: Date.new(2027, 12, 20)) }
  let(:valid) { { time_period: { name: "Winter", start_date: "2028-01-05", end_date: "2028-04-20" } } }

  describe "role matrix" do
    let(:calls) do
      {
        index: -> { get admin_time_periods_path },
        new: -> { get new_admin_time_period_path },
        edit: -> { get edit_admin_time_period_path(period) },
        create: -> { post admin_time_periods_path, params: valid },
        update: -> { patch admin_time_period_path(period), params: valid },
        destroy: -> { delete admin_time_period_path(period) }
      }
    end

    %i[guest regular staff].each do |role|
      it "bounces #{role} to / without changes" do
        expect_bounced(role, calls, state: -> { TimePeriod.order(:id).map(&:attributes) })
      end
    end
  end

  context "as admin" do
    before { sign_in_as(:admin) }

    it "renders index, new and edit" do
      get admin_time_periods_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Fall", "09/ 1/2027", "12/20/2027")
      get new_admin_time_period_path
      expect(response).to have_http_status(:ok)
      get edit_admin_time_period_path(period)
      expect(response).to have_http_status(:ok)
      get edit_admin_time_period_path(0)
      expect(response).to have_http_status(:not_found)
    end

    it "creates and redirects to the index with a notice" do
      expect { post admin_time_periods_path, params: valid }.to change(TimePeriod, :count).by(1)
      expect(response).to redirect_to(admin_time_periods_path)
      expect(flash[:notice]).to eq("You have successfully created a new time period!")
      expect(TimePeriod.find_by!(name: "Winter")).to have_attributes(start_date: Date.new(2028, 1, 5), end_date: Date.new(2028, 4, 20))
    end

    it "redirects home with the ParameterMissing message when time_period is absent" do
      post admin_time_periods_path
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to match(/time_period/)
    end

    # WART(D-SP06): TimePeriod has no validations: blank dates (and end before start) are accepted.
    it "accepts blank dates and an inverted range" do
      post admin_time_periods_path, params: { time_period: { name: "", start_date: "2028-05-01", end_date: "2028-01-01" } }
      expect(response).to redirect_to(admin_time_periods_path)
      expect(TimePeriod.find_by(name: "")).to have_attributes(start_date: Date.new(2028, 5, 1), end_date: Date.new(2028, 1, 1))
    end

    # WART(D-SP07): one time period with nil dates makes the whole index page 500 (strftime on nil).
    it "index 500s once a period without dates exists" do
      post admin_time_periods_path, params: { time_period: { name: "Broken", start_date: "", end_date: "" } }
      expect(response).to redirect_to(admin_time_periods_path)
      get admin_time_periods_path
      expect(response).to have_http_status(:internal_server_error)
    end

    it "updates with a notice" do
      patch admin_time_period_path(period), params: { time_period: { name: "Autumn" } }
      expect(response).to redirect_to(admin_time_periods_path)
      expect(flash[:notice]).to eq("Time Period updated")
      expect(period.reload.name).to eq("Autumn")
    end

    it "destroys the period and its staff availabilities" do
      create(:staff_availability, time_period: period)
      expect { delete admin_time_period_path(period) }
        .to change(TimePeriod, :count).by(-1).and change(StaffAvailability, :count).by(-1)
      expect(response).to redirect_to(admin_time_periods_path)
      expect(flash[:notice]).to eq("Time Period Deleted")
    end

    it "404s for update/destroy of an unknown id" do
      patch admin_time_period_path(0), params: valid
      expect(response).to have_http_status(:not_found)
      delete admin_time_period_path(0)
      expect(response).to have_http_status(:not_found)
    end
  end
end
