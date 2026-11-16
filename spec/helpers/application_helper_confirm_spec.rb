# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#confirmation_data" do
    it "returns the data attributes that make an element ask its message on click" do
      expect(helper.confirmation_data("Sure?")).to eq(
        controller: "confirmation",
        action: "click->confirmation#ask",
        confirmation_message_value: "Sure?"
      )
    end
  end

  describe "#confirmation_options" do
    it "returns a disabled button's options with the confirmation data" do
      expect(helper.confirmation_options("Sure?")).to eq(
        disabled: true,
        data: helper.confirmation_data("Sure?")
      )
    end
  end
end
