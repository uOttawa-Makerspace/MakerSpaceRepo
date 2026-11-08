# frozen_string_literal: true

require "rails_helper"

# The staff dashboard tables say when and where a user was last seen. "Latest session" is
# the user's newest session (highest id) in any space, however the database returns the
# rows, and every table must name it from the same full set of the user's sessions.
RSpec.describe "Staff dashboard last visit cells", type: :request do
  include StaffDashboardSpecHelpers

  let!(:space) { create(:space, name: "Here Lab") }
  let!(:elsewhere) { create(:space, name: "Elsewhere Lab") }
  let!(:staff) { sign_in_as(:staff, space: space) }
  let(:visitor) { create(:user, :regular_user, name: "Mixed Visitor", username: "mixedvisitor") }

  # An older session in another space that is rewritten after the newer ones, so the
  # database returns it last. The space column is indexed, so changing it moves the row
  # to the end of both the table and the user_id index (a plain update can leave an index
  # scan in id order).
  def rewrite_older_session
    older = create(:lab_session, user: visitor, space: space, sign_in_time: 6.hours.ago, sign_out_time: 5.hours.ago)
    yield
    older.update!(space: elsewhere)
  end

  def cell_texts(html, selector)
    Nokogiri::HTML(html).css(selector).map { |cell| cell.text.squish }
  end

  context "when the user is signed in here and has an older visit elsewhere" do
    before do
      rewrite_older_session do
        create(:lab_session, user: visitor, space: space, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
      end
    end

    it "names the latest session's space in the dashboard index rows" do
      get "/staff_dashboard"

      expect(response).to have_http_status(:ok)
      expect(cell_texts(response.body, "tr[data-user-id='#{visitor.id}'] td.align-middle")).to include("about 5 hours ago at Elsewhere Lab")
    end

    it "names the latest session's space in the search signed-in table" do
      get "/staff_dashboard/search", params: { username: visitor.username }

      expect(response).to have_http_status(:ok)
      expect(cell_texts(response.body, "td.sign_out_time-cell")).to include("about 5 hours ago at Elsewhere Lab")
    end
  end

  context "when the user has three visits in different spaces" do
    before do
      create(:lab_session, user: visitor, space: elsewhere, sign_in_time: 9.hours.ago, sign_out_time: 8.hours.ago)
      create(:lab_session, user: visitor, space: space, sign_in_time: 6.hours.ago, sign_out_time: 5.hours.ago)
      create(:lab_session, user: visitor, space: elsewhere, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
    end

    it "shows the end and the space of the second newest visit, not the newest one's" do
      get "/staff_dashboard/search", params: { username: visitor.username }

      expect(cell_texts(response.body, "td.signed_in-cell")).to eq(["about 2 hours ago at Elsewhere Lab"])
      expect(cell_texts(response.body, "td.sign_out_time-cell")).to include("about 5 hours ago at Here Lab")
    end
  end

  context "when the user has left and the latest session is the one in this space" do
    before do
      rewrite_older_session do
        create(:lab_session, user: visitor, space: space, sign_in_time: 2.hours.ago, sign_out_time: 1.hour.ago)
      end
    end

    it "names the latest session's space in the search result's last seen cell" do
      get "/staff_dashboard/search", params: { username: visitor.username }

      expect(cell_texts(response.body, "td.signed_in-cell")).to eq(["about 1 hour ago at Here Lab"])
    end
  end

  context "when the user signed out of this space" do
    before do
      rewrite_older_session do
        create(:lab_session, user: visitor, space: space, sign_in_time: 4.hours.ago, sign_out_time: 3.hours.ago)
        create(:lab_session, user: visitor, space: elsewhere, sign_in_time: 2.hours.ago, sign_out_time: 1.hour.ago)
      end
    end

    it "shows the last visit to this space in the signed-out table" do
      get "/staff_dashboard/search", params: { username: visitor.username }

      expect(cell_texts(response.body, "td.sign_out_time-cell")).to include("about 3 hours ago at Here Lab")
    end
  end

  describe "refresh_tables", skip_bullet: true do
    before do
      rewrite_older_session do
        create(:lab_session, user: visitor, space: space, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
      end
    end

    it "names the latest session's space in the signed-in table" do
      get "/staff_dashboard/refresh_tables"

      expect(cell_texts(json["signed_in"], "td.sign_out_time-cell")).to include("about 5 hours ago at Elsewhere Lab")
    end
  end
end
