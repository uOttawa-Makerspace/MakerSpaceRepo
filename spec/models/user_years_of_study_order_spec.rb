# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, ".years_of_study_in_order" do
  it "keeps each year its own count and orders numbered years, Alumni, N/A, other text, then blank" do
    counts = { "N/A" => 4, nil => 1, "" => 2, "Alumni" => 3, "10" => 5, "2" => 6, "Other" => 7, "1" => 8 }
    expect(described_class.years_of_study_in_order(counts)).to eq(
      [[1, 8], [2, 6], [10, 5], ["Alumni", 3], ["N/A", 4], ["Other", 7], ["Unknown", 3]]
    )
  end

  it "takes numbered years given as numbers" do
    expect(described_class.years_of_study_in_order({ 3 => 1, "Alumni" => 2, 1 => 4 }))
      .to eq([[1, 4], [3, 1], ["Alumni", 2]])
  end

  it "counts a stored Unknown with the users who have no year" do
    expect(described_class.years_of_study_in_order({ "Unknown" => 2, nil => 1, "1" => 1 }))
      .to eq([[1, 1], ["Unknown", 3]])
  end

  it "gives nothing for no counts" do
    expect(described_class.years_of_study_in_order({})).to eq([])
  end
end
