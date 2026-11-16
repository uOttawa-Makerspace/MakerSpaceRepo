# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/job_options/_form", type: :view do
  def render_form(option)
    assign(:job_option, option)
    render partial: "admin/job_options/form"
    rendered
  end

  it "counts the option's validation errors in the heading" do
    option = JobOption.new
    option.errors.add(:name, "is required")
    option.errors.add(:fee, "is required")

    html = render_form(option)

    expect(html).to include("2 errors prohibited this option from being saved:")
    expect(html).to include("Name is required")
  end

  it "uses the singular heading for one error" do
    option = JobOption.new
    option.errors.add(:name, "is required")

    expect(render_form(option)).to include("1 error prohibited this option from being saved:")
  end

  it "shows no error heading for a valid option" do
    expect(render_form(JobOption.new)).not_to include("prohibited this option")
  end
end
