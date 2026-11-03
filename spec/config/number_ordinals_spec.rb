# frozen_string_literal: true

require "rails_helper"

# Integer#ordinalize asks I18n for number.nth.ordinalized; French has to answer it.
RSpec.describe "Ordinal numbers in each language" do
  it "ordinalizes in English" do
    I18n.with_locale(:en) { expect([1, 2, 3, 4, 11, 21].map(&:ordinalize)).to eq(%w[1st 2nd 3rd 4th 11th 21st]) }
  end

  it "ordinalizes in French: 1er, then e" do
    I18n.with_locale(:fr) { expect([1, 2, 3, 11, 21].map(&:ordinalize)).to eq(%w[1er 2e 3e 11e 21e]) }
  end
end
