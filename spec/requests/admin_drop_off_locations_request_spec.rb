# frozen_string_literal: true

require "rails_helper"

# Admin::DropOffLocationsController. Guests go to the login page, other non-admins to "/".

RSpec.describe "Admin drop-off locations", type: :request do
  include SpacesSpecHelpers

  let!(:location) { create(:drop_off_location, name: "Dock") }

  describe "role matrix" do
    let(:calls) do
      {
        index: -> { get admin_drop_off_locations_path },
        new: -> { get new_admin_drop_off_location_path },
        edit: -> { get edit_admin_drop_off_location_path(location) },
        create: -> { post admin_drop_off_locations_path, params: { name: "Nope" } },
        update: -> { patch admin_drop_off_location_path(location), params: { drop_off_location: { name: "Nope" } } },
        destroy: -> { delete admin_drop_off_location_path(location) }
      }
    end

    %i[guest regular staff].each do |role|
      it "bounces #{role} to / without changes" do
        expect_bounced(role, calls, state: -> { DropOffLocation.order(:id).map(&:attributes) })
      end
    end
  end

  context "as admin" do
    before { sign_in_as(:admin) }

    it "renders index, new and edit" do
      get admin_drop_off_locations_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Dock")
      get new_admin_drop_off_location_path
      expect(response).to have_http_status(:ok)
      get edit_admin_drop_off_location_path(location)
      expect(response).to have_http_status(:ok)
      get edit_admin_drop_off_location_path(0)
      expect(response).to have_http_status(:not_found)
    end

    it "has a show route but no show action (404)" do
      get admin_drop_off_location_path(location)
      expect(response).to have_http_status(:not_found)
    end

    it "creates from the top-level name param" do
      expect { post admin_drop_off_locations_path, params: { name: "Lab door" } }.to change(DropOffLocation, :count).by(1)
      expect(response).to redirect_to(admin_drop_off_locations_path)
      expect(flash[:notice]).to eq("Drop-off Location added successfully!")
      expect(DropOffLocation.last.name).to eq("Lab door")
    end

    it "refuses a blank or missing name" do
      expect { post admin_drop_off_locations_path, params: { name: "" } }.not_to change(DropOffLocation, :count)
      expect(response).to redirect_to(admin_drop_off_locations_path)
      expect(flash[:alert]).to eq("Input is invalid")
      expect { post admin_drop_off_locations_path, params: { name: "  " } }.not_to change(DropOffLocation, :count)
      expect { post admin_drop_off_locations_path }.not_to change(DropOffLocation, :count)
      expect(flash[:alert]).to eq("Input is invalid")
    end

    it "keeps the name when it is renamed to a blank one" do
      patch admin_drop_off_location_path(location), params: { drop_off_location: { name: "" } }
      expect(response).to redirect_to(admin_drop_off_locations_path)
      expect(flash[:alert]).to eq("Input is invalid")
      expect(location.reload.name).to eq("Dock")
    end

    it "renames from drop_off_location[name]" do
      patch admin_drop_off_location_path(location), params: { drop_off_location: { name: "Dock 2" } }
      expect(response).to redirect_to(admin_drop_off_locations_path)
      expect(flash[:notice]).to eq("Drop-off Location renamed successfully")
      expect(location.reload.name).to eq("Dock 2")
    end

    it "update without the nested param redirects with the missing-parameter message and keeps the name" do
      patch admin_drop_off_location_path(location)
      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to match(/drop_off_location/)
      expect(location.reload.name).to eq("Dock")
    end

    it "destroys with a notice" do
      expect { delete admin_drop_off_location_path(location) }.to change(DropOffLocation, :count).by(-1)
      expect(response).to redirect_to(admin_drop_off_locations_path)
      expect(flash[:notice]).to eq("Drop-off Location Deleted successfully")
    end
  end
end
