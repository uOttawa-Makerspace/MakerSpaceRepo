# frozen_string_literal: true

require "rails_helper"

# Admin::DropOffLocationsController. Non-admins bounce to "/".

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

    # WART(D-SP10): DropOffLocation has no validations: a blank/missing name is saved, so the "Input is invalid" branch is unreachable.
    it "saves a blank name" do
      expect { post admin_drop_off_locations_path, params: { name: "" } }.to change(DropOffLocation, :count).by(1)
      expect(flash[:notice]).to eq("Drop-off Location added successfully!")
      expect(flash[:alert]).to be_nil
    end

    it "renames from drop_off_location[name]" do
      patch admin_drop_off_location_path(location), params: { drop_off_location: { name: "Dock 2" } }
      expect(response).to redirect_to(admin_drop_off_locations_path)
      expect(flash[:notice]).to eq("Drop-off Location renamed successfully")
      expect(location.reload.name).to eq("Dock 2")
    end

    # WART(D-SP11): update reads params[:drop_off_location][:name] unguarded: no nested param is a NoMethodError 500.
    it "update 500s when the nested param is missing" do
      patch admin_drop_off_location_path(location)
      expect(response).to have_http_status(:internal_server_error)
      expect(location.reload.name).to eq("Dock")
    end

    it "destroys with a notice" do
      expect { delete admin_drop_off_location_path(location) }.to change(DropOffLocation, :count).by(-1)
      expect(response).to redirect_to(admin_drop_off_locations_path)
      expect(flash[:notice]).to eq("Drop-off Location Deleted successfully")
    end
  end
end
