# frozen_string_literal: true

require "rails_helper"

# The browser keeps the real clock while an example may freeze the server's
# (travel_to). The session must survive that, whichever clock is later.
RSpec.describe "Browser session on a frozen server clock", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :regular_user) }

  it "stays signed in when the server clock is frozen more than a week before the real date" do
    travel_to(Time.zone.local(2026, 1, 1, 12)) do
      log_in_as(user)
      visit root_path
      expect_signed_in
    end
  end

  it "stays signed in when the server clock is frozen in the future" do
    travel_to(Time.zone.local(2040, 1, 1, 12)) do
      log_in_as(user)
      visit root_path
      expect_signed_in
    end
  end
end
