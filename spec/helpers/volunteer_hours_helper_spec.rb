# frozen_string_literal: true

require "rails_helper"

RSpec.describe VolunteerHoursHelper do
  it "describes the approval of a volunteer hour in the current language" do
    expect([nil, true, false].map { |approval| helper.return_approval(approval) }).to eq(["Not Accessed", "Approved", "Not Approved"])
    I18n.with_locale(:fr) do
      expect([nil, true, false].map { |approval| helper.return_approval(approval) }).to eq(["Non évaluée", "Approuvée", "Non approuvée"])
    end
  end
end
