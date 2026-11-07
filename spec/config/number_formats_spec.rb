# frozen_string_literal: true

require "rails_helper"

# English writes "$58.50"; French writes "58,50 $" with a no-break space before the symbol.
RSpec.describe "Number and currency formats in each language", type: :helper do
  helper_class = JobOrdersHelper
  before { helper.extend(helper_class) }
  nbsp = " "

  it "formats money in English as $58.50" do
    I18n.with_locale(:en) { expect(helper.number_to_currency(58.5)).to eq("$58.50") }
  end

  it "formats money in French as 58,50 $" do
    I18n.with_locale(:fr) { expect(helper.number_to_currency(58.5)).to eq("58,50#{nbsp}$") }
  end

  it "groups thousands in French with a no-break space" do
    I18n.with_locale(:fr) { expect(helper.number_to_currency(1234.5)).to eq("1#{nbsp}234,50#{nbsp}$") }
  end

  it "formats plain numbers in French with a decimal comma" do
    I18n.with_locale(:fr) { expect(helper.number_with_precision(3.5, precision: 2)).to eq("3,50") }
  end

  it "lets the locale be chosen per call, as in the two-language quote mail" do
    I18n.with_locale(:en) { expect(helper.number_to_currency(58.5, locale: :fr)).to eq("58,50#{nbsp}$") }
  end

  describe "the default shown in a number input" do
    it "keeps a dot and no grouping in French, which a browser number input requires" do
      I18n.with_locale(:fr) { expect(helper.money_input_value(1234.5)).to eq("1234.50") }
    end
  end
end
