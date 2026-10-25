require "rails_helper"

# Chunk 15: Admin::PiReadersController#update (AdminAreaController: non-admins,
# guests included, are redirected to "/" silently, no flash).
RSpec.describe "Admin pi readers", type: :request do
  let(:pi_reader) { create(:pi_reader) }
  let(:space) { create(:space) }
  let(:params) { { id: pi_reader.id, pi_reader_params: { space_id: space.id, pi_location: "Bench 4" } } }

  %i[guest regular staff volunteer].each do |role|
    it "redirects a #{role} to / without updating" do
      sign_in_as(role)
      patch admin_pi_reader_path(pi_reader), params: params
      expect(response).to redirect_to("/")
      expect(pi_reader.reload.pi_location).to eq("Room Location")
    end
  end

  it "updates space and location for an admin and redirects back with a notice" do
    sign_in_as(:admin)
    patch admin_pi_reader_path(pi_reader), params: params, headers: { "HTTP_REFERER" => admin_keys_url }
    expect(response).to redirect_to(admin_keys_url)
    expect(flash[:notice]).to eq("Updated successfully")
    expect(pi_reader.reload).to have_attributes(space_id: space.id, pi_location: "Bench 4")
  end

  it "falls back to root without a referer" do
    sign_in_as(:admin)
    patch admin_pi_reader_path(pi_reader), params: params
    expect(response).to redirect_to(root_path)
  end

  it "ignores unpermitted attributes such as the mac address" do
    sign_in_as(:admin)
    patch admin_pi_reader_path(pi_reader), params: { id: pi_reader.id, pi_reader_params: { pi_mac_address: "zz", pi_location: "x" } }
    expect(pi_reader.reload.pi_mac_address).not_to eq("zz")
  end

  it "raises RecordNotFound (404) for an unknown reader" do
    sign_in_as(:admin)
    patch admin_pi_reader_path(0), params: params
    expect(response).to have_http_status(:not_found)
  end

  it "redirects to root with the ParameterMissing message when pi_reader_params is missing" do
    sign_in_as(:admin)
    patch admin_pi_reader_path(pi_reader), params: { foo: 1 }
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to match(/pi_reader_params/)
  end
end
