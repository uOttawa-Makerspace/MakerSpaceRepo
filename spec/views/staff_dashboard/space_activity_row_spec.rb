# frozen_string_literal: true

require "rails_helper"

# The staff dashboard row names the space of the user's latest lab session, however the
# database happens to return the user's sessions.
RSpec.describe "staff_dashboard/_space_activity_row", type: :view do
  let(:here) { create(:space, name: "Here Lab") }
  let(:elsewhere) { create(:space, name: "Elsewhere Lab") }
  let(:user) { create(:user, :regular_user) }

  def render_row
    ApplicationController.render(
      partial: "staff_dashboard/space_activity_row",
      collection: [User.find(user.id)],
      locals: { space: here, signed_out: true }
    )
  end

  it "names the space of the latest session when an older session was rewritten after it" do
    older = create(:lab_session, user: user, space: elsewhere, sign_in_time: 3.hours.ago, sign_out_time: 2.hours.ago)
    create(:lab_session, user: user, space: here, sign_in_time: 1.hour.ago, sign_out_time: 30.minutes.ago)
    # An update writes a new row version after the newer session's row, so the sessions
    # come back from the database with the older one last.
    older.update!(sign_out_time: 100.minutes.ago)

    expect(render_row).to include("ago at Here Lab")
  end
end
