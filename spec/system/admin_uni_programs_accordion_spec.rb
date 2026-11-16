# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin uni programs accordion", type: :system do
  let(:admin) { create(:user, :admin) }

  it "expands an Engineering department to show its programs" do
    create(:uni_program, program: "Software Engineering", level: "Bachelor's",
                         faculty: "Engineering", department: "EECS")
    log_in_as(admin, to: admin_uni_programs_index_path)

    programs = "td"
    faculty = "#accordion-Engineering"
    department = "#accordion-EECS"

    expect(page).to have_no_css(programs, text: "Software Engineering", visible: :visible)
    find(".card-header", text: /\AEngineering - 1 programs/).click
    expect(page).to have_css("#{faculty}.collapse.show")
    expect(page).to have_no_css(".collapsing")
    expect(page).to have_no_css(programs, text: "Software Engineering", visible: :visible)
    department_button = find("button[data-bs-target='#{department}']")
    expect(department_button["aria-expanded"]).to eq("false")

    find(".card-header", text: /EECS - 1 programs/).click
    expect(page).to have_css("#{department}.collapse.show")
    expect(page).to have_css("button[data-bs-target='#{department}'][aria-expanded='true']")
    expect(page).to have_no_css(".collapsing")
    expect(page).to have_css(programs, text: "Software Engineering", visible: :visible)

    find(".card-header", text: /EECS - 1 programs/).click
    expect(page).to have_no_css("#{department}.show")
    expect(page).to have_no_css(".collapsing")
    expect(page).to have_no_css(programs, text: "Software Engineering", visible: :visible)
  end
end
