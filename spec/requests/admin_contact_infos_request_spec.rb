# frozen_string_literal: true

require "rails_helper"

# Characterization spec for Admin::ContactInfosController (chunk 9 "Identity"):
# admin-only CRUD, with the odd name-from-space_id behavior on create.

RSpec.describe "Admin::ContactInfos (HTTP contract)", type: :request do
  let(:password) { "asa32A353#" }
  let(:admin) { create(:user, :admin) }
  let(:staff) { create(:user, :staff) }
  let(:regular) { create(:user, :regular_user) }
  let!(:info) { create(:contact_info, name: "Front Desk") }

  before { block_external_http! }

  def login!(u)
    post login_authentication_path, params: { username_email: u.username, password: password }
  end

  def valid_params(extra = {})
    { contact_info: { space_id: "Custom Label", email: "x@example.com", address: "1 Main",
                      phone_number: "555", url: "http://x.test", show_hours: "0" }.merge(extra) }
  end

  describe "authorization: non-admins are bounced to /" do
    { guest: nil, regular: :regular, staff: :staff }.each do |role, who|
      context "as #{role}" do
        before { login!(send(who)) if who }

        it "refuses every action and changes nothing" do
          get admin_contact_infos_path
          expect(response.location).to eq("http://www.example.com/")
          get new_admin_contact_info_path
          expect(response.location).to eq("http://www.example.com/")
          get edit_admin_contact_info_path(info)
          expect(response.location).to eq("http://www.example.com/")
          expect { post admin_contact_infos_path, params: valid_params }.not_to change(ContactInfo, :count)
          expect(response.location).to eq("http://www.example.com/")
          patch admin_contact_info_path(info), params: { contact_info: { name: "Hacked" } }
          expect(response.location).to eq("http://www.example.com/")
          expect(info.reload.name).to eq("Front Desk")
          expect { delete admin_contact_info_path(info) }.not_to change(ContactInfo, :count)
          expect(response.location).to eq("http://www.example.com/")
        end
      end
    end
  end

  describe "as admin" do
    before { login!(admin) }

    it "index lists contacts ordered by name" do
      create(:contact_info, name: "Aardvark Office")
      get admin_contact_infos_path
      expect(response).to have_http_status(:ok)
      expect(response.body.index("Aardvark Office")).to be < response.body.index("Front Desk")
    end

    it "new renders" do
      get new_admin_contact_info_path
      expect(response).to have_http_status(:ok)
    end

    it "edit renders" do
      get edit_admin_contact_info_path(info)
      expect(response).to have_http_status(:ok)
    end

    it "show 404s (the route exists but the controller defines no show)" do
      # WART(D-I26): routes expose GET /admin/contact_infos/:id but the controller has no show action or view
      get admin_contact_info_path(info)
      expect(response).to have_http_status(:not_found)
    end

    it "create with a non-space value uses it as the name and nils space_id" do
      expect { post admin_contact_infos_path, params: valid_params }.to change(ContactInfo, :count).by(1)
      expect(response).to redirect_to(admin_contact_infos_path)
      expect(flash[:notice]).to eq("You've successfully created a new Contact Info !")
      created = ContactInfo.order(:id).last
      expect(created.name).to eq("Custom Label")
      expect(created.space_id).to be_nil
      expect(created.email).to eq("x@example.com")
    end

    it "create with a real space id copies the space name" do
      space = create(:space)
      post admin_contact_infos_path, params: valid_params(space_id: space.id.to_s)
      created = ContactInfo.order(:id).last
      expect(created.name).to eq(space.name)
      expect(created.space_id).to eq(space.id)
    end

    it "create saves nested opening hours (rejecting rows without target_en/target_fr)" do
      post admin_contact_infos_path,
           params: valid_params(opening_hours_attributes: {
                                  "0" => { target_en: "Week", target_fr: "Semaine", monday_opening: "09:00" },
                                  "1" => { target_en: "", target_fr: "" }
                                })
      expect(ContactInfo.order(:id).last.opening_hours.count).to eq(1)
    end

    it "create without the contact_info param 500s (nil[] on the missing hash)" do
      # WART(D-I27): create dereferences params[:contact_info][...] before strong params, so a missing hash is a 500, not the app's ParameterMissing redirect
      expect { post admin_contact_infos_path, params: {} }.not_to change(ContactInfo, :count)
      expect(response).to have_http_status(:internal_server_error)
    end

    it "update changes fields and redirects with notice" do
      patch admin_contact_info_path(info), params: { contact_info: { name: "Renamed", phone_number: "123" } }
      expect(response).to redirect_to(admin_contact_infos_path)
      expect(flash[:notice]).to eq("Contact Info updated")
      expect(info.reload.name).to eq("Renamed")
      expect(info.phone_number).to eq("123")
    end

    it "update can add and destroy nested opening hours" do
      patch admin_contact_info_path(info),
            params: { contact_info: { opening_hours_attributes: { "0" => { target_en: "A", target_fr: "B" } } } }
      oh = info.opening_hours.reload.first
      expect(oh).to be_present
      patch admin_contact_info_path(info),
            params: { contact_info: { opening_hours_attributes: { "0" => { id: oh.id, _destroy: "1" } } } }
      expect(info.opening_hours.reload).to be_empty
    end

    it "destroy removes the contact and its opening hours" do
      info.opening_hours.create!(target_en: "A", target_fr: "B")
      expect { delete admin_contact_info_path(info) }.to change(ContactInfo, :count).by(-1)
      expect(response).to redirect_to(admin_contact_infos_path)
      expect(flash[:notice]).to eq("Contact Info Deleted")
      expect(OpeningHour.where(contact_info_id: info.id)).to be_empty
    end

    it "unknown id: 404" do
      get edit_admin_contact_info_path(0)
      expect(response).to have_http_status(:not_found)
    end

    it "ContactInfo has no validations: blank records persist" do
      expect { post admin_contact_infos_path, params: valid_params(space_id: "", email: "") }
        .to change(ContactInfo, :count).by(1)
      expect(ContactInfo.order(:id).last.name).to eq("")
    end
  end
end
