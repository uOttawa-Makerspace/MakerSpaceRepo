# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin uni programs accordion", type: :system do
  let(:admin) { create(:user, :admin) }

  it "expands an Engineering department to show its programs" do
    create(:uni_program, program: "Software Engineering", level: "Bachelor's", faculty: "Engineering", department: "EECS")
    log_in_as(admin, to: admin_uni_programs_index_path)

    expect(page).not_to have_css("td", text: "Software Engineering", visible: :visible)
    find(".card-header", text: /\AEngineering - 1 programs/).click
    expect(page).to have_css(".card-header", text: /EECS - 1 programs/)
    expect(page).not_to have_css("td", text: "Software Engineering", visible: :visible)

    find(".card-header", text: /EECS - 1 programs/).click
    expect(page).to have_css("td", text: "Software Engineering", visible: :visible)

    find(".card-header", text: /EECS - 1 programs/).click
    expect(page).not_to have_css("td", text: "Software Engineering", visible: :visible)
  end
end
