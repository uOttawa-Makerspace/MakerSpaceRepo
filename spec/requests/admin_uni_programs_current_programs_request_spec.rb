# frozen_string_literal: true

require "rails_helper"

# GET /admin/uni_programs/current_programs: download of the programs file shipped in lib/assets.
RSpec.describe "Admin uni programs current programs", type: :request do
  include SpacesSpecHelpers

  before { sign_in_as(:admin) }

  it "sends the programs csv" do
    get "/admin/uni_programs/current_programs"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/csv")
    expect(response.body).to start_with("program,level,faculty,department")
  end

  it "redirects to the programs page with a message when the file is missing" do
    allow(Rails.root).to receive(:join).and_call_original
    allow(Rails.root).to receive(:join).with("lib/assets/programs.csv").and_return(Pathname("/nonexistent/programs.csv"))
    get "/admin/uni_programs/current_programs"
    expect(response).to redirect_to(admin_uni_programs_index_path)
    expect(flash[:alert]).to eq(I18n.t("errors.admin.uni_programs.programs_file_missing"))
  end
end
