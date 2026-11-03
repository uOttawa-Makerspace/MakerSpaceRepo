# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#issued_date" do
    {
      en: { 1 => "November 1st, 2026", 2 => "November 2nd, 2026", 3 => "November 3rd, 2026", 11 => "November 11th, 2026" },
      fr: { 1 => "1er novembre 2026", 2 => "2 novembre 2026", 3 => "3 novembre 2026", 11 => "11 novembre 2026" }
    }.each do |locale, days|
      days.each do |day, text|
        it "words day #{day} in #{locale} as #{text}" do
          I18n.with_locale(locale) { expect(helper.issued_date(Date.new(2026, 11, day))).to eq(text) }
        end
      end
    end
  end
end
