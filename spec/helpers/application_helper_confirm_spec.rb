# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#confirmed_until_ready" do
    it "returns a disabled button's options with the enabling controller and the message" do
      expect(helper.confirmed_until_ready("Sure?")).to eq(
        disabled: true,
        data: { controller: "enable-when-ready", confirm: "Sure?" }
      )
    end
  end
end
