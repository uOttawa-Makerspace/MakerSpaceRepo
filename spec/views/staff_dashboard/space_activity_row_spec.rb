# frozen_string_literal: true

require "rails_helper"

# The staff dashboard row names the end and the space of the user's previous visit (the
# second newest session), however the database happens to return the user's sessions.
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

  it "names the previous visit's space when it was rewritten after the newer session" do
    older = create(:lab_session, user: user, space: elsewhere, sign_in_time: 3.hours.ago, sign_out_time: 2.hours.ago)
    create(:lab_session, user: user, space: here, sign_in_time: 1.hour.ago, sign_out_time: 30.minutes.ago)
    # An update writes a new row version after the newer session's row, so the sessions
    # come back from the database with the older one last.
    older.update!(sign_out_time: 100.minutes.ago)

    expect(render_row).to include("about 2 hours ago at Elsewhere Lab")
  end

  describe "certification date" do
    let(:ceed) { create(:space, name: "CEED") }

    before do
      create(:certification, user: user).update_columns(updated_at: Time.zone.local(2026, 11, 2, 10))
    end

    def render_signed_in_row(locale)
      I18n.with_locale(locale) do
        ApplicationController.render(partial: "staff_dashboard/space_activity_row", collection: [User.find(user.id)], locals: { space: ceed })
      end
    end

    it "reads month, day, year in English" do
      expect(render_signed_in_row(:en)).to include("November 02, 2026")
    end

    it "reads day, month, year in French" do
      expect(render_signed_in_row(:fr)).to include("2 novembre 2026")
    end
  end
end
