# frozen_string_literal: true

require "rails_helper"

# Checkboxes built with check_box_tag: the submitted value is a plain "1" (or the record id)
# and a box starts ticked only when the page says so.
RSpec.describe "Checkbox defaults", type: :request do
  include SpacesSpecHelpers

  def checkbox(selector)
    Nokogiri::HTML(response.body).at_css(selector)
  end

  it "renders the liked filter unticked until it is asked for, valued 1" do
    sign_in_as(:regular)
    get explore_path
    expect(checkbox("input#liked")["value"]).to eq("1")
    expect(checkbox("input#liked")["checked"]).to be_nil
    get search_path(liked: "1")
    expect(checkbox("input#liked")["checked"]).to be_present
  end

  it "renders the help form's share-email box unticked, valued 1" do
    sign_in_as(:regular)
    get help_path
    expect(checkbox("input#share_email")["value"]).to eq("1")
    expect(checkbox("input#share_email")["checked"]).to be_nil
  end

  it "renders the staff dashboard popup switch ticked, valued 1" do
    sign_in_as(:staff, space: create(:space))
    get staff_dashboard_index_path
    expect(checkbox("input#popup_enabled")["value"]).to eq("1")
    expect(checkbox("input#popup_enabled")["checked"]).to be_present
  end

  it "renders the new faculties box on the university programs page unticked, valued 1" do
    sign_in_as(:admin)
    get admin_uni_programs_index_path
    expect(checkbox("input#allow_new_programs")["value"]).to eq("1")
    expect(checkbox("input#allow_new_programs")["checked"]).to be_nil
  end
end
