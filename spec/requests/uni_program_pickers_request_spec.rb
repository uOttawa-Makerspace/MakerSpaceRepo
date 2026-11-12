# frozen_string_literal: true

require "rails_helper"

# The sign-up and profile forms offer active programs only; a user's stored program keeps resolving.
RSpec.describe "University program pickers", type: :request do
  include SpacesSpecHelpers

  before do
    create(:uni_program, program: "Active Program", faculty: "Engineering")
    create(:uni_program, program: "Retired Program", faculty: "Engineering", active: false)
  end

  it "lists only active programs on the sign-up form" do
    get new_user_path

    expect(response.body).to include("Active Program")
    expect(response.body).not_to include("Retired Program")
  end

  it "lists only active programs on the profile form" do
    sign_in_as(:regular)
    get "/settings/profile"

    expect(response.body).to include("Active Program")
    expect(response.body).not_to include("Retired Program")
  end

  it "keeps a retired program on the profile form of the user who has it" do
    sign_in_as(:regular, program: "Retired Program")
    get "/settings/profile"

    expect(response.body).to include("Retired Program")
  end
end
