# frozen_string_literal: true

require "rails_helper"

# The staff dashboard of the space named "Makerspace" has an "Assigned Printers" column:
# each signed-in row lists the printers that user has in use. Every response that renders
# the signed-in rows (the page, the refresh_tables JSON, the sign-in and sign-out JS
# responses and the live broadcast) shows the same printers. Other spaces have no column.
RSpec.describe "Staff dashboard printers column", type: :request do
  include StaffDashboardSpecHelpers
  include_context "with test cable adapter"

  let(:visitor) { create(:user, :regular_user) }
  let(:neighbour) { create(:user, :regular_user) }
  let(:leaving) { create(:user, :regular_user) }
  let(:um2p) { create(:printer, :UM2P_02) }
  let(:rpl2) { create(:printer, :RPL2_01) }
  let(:released) { create(:printer, :UM3_01) }

  before do
    create(:printer_session, user: visitor, printer: um2p, in_use: true)
    create(:printer_session, user: visitor, printer: rpl2, in_use: true)
    create(:printer_session, user: visitor, printer: released, in_use: false)
  end

  def printers_cells(html)
    Nokogiri::HTML(html).css("td.printers-cell")
  end

  def expect_visitor_printers(html)
    cell = Nokogiri::HTML(html).at_css("tr[data-user-id='#{visitor.id}'] td.printers-cell")
    expect(cell).to be_present
    expect(cell.css("p").map(&:text)).to contain_exactly(um2p.name, rpl2.name)
  end

  # The sign-in and sign-out JS responses write the rendered rows into the page.
  def signed_in_rows_from_js
    response.body.lines.find { |line| line.include?("table-js-signed-in") }.then do |line|
      line[/innerHTML = "(.*)"\s*\z/, 1].gsub(/\\(.)/) { Regexp.last_match(1) == "n" ? "\n" : Regexp.last_match(1) }
    end
  end

  shared_examples "the signed-in rows of every response" do
    let!(:staff) { sign_in_as(:staff, space: space) }

    before do
      sign_in_session(visitor, space)
      sign_in_session(neighbour, space)
      sign_in_session(leaving, space)
    end

    it "renders them on the dashboard page" do
      get staff_dashboard_index_path

      expect(response).to have_http_status(:ok)
      check_rows(response.body)
    end

    it "renders them in the refresh_tables JSON" do
      get "/staff_dashboard/refresh_tables"

      expect(response).to have_http_status(:ok)
      check_rows(json["signed_in"])
    end

    it "renders them in the sign-in JS response" do
      put "/staff_dashboard/add_users", params: { added_users: [create(:user, :regular_user).username] }, as: :js, xhr: true

      expect(response).to have_http_status(:ok)
      check_rows(signed_in_rows_from_js)
    end

    it "renders them in the sign-out JS response" do
      put "/staff_dashboard/remove_users", params: { dropped_users: [leaving.username] }, as: :js, xhr: true

      expect(response).to have_http_status(:ok)
      check_rows(signed_in_rows_from_js)
    end

    it "renders them in the live table broadcast" do
      expect { StaffDashboardChannel.broadcast_table_updates(space.id) }
        .to have_broadcasted_to(StaffDashboardChannel.table_stream(space.id, :en)).from_channel(Turbo::StreamsChannel).with { |html| check_rows(html) }
    end
  end

  context "in the Makerspace space" do
    let!(:space) { create(:space, name: "Makerspace") }

    # Released printers are left out, and a user with no printer in use has an empty cell.
    def check_rows(html)
      expect_visitor_printers(html)
      expect(Nokogiri::HTML(html).at_css("tr[data-user-id='#{neighbour.id}'] td.printers-cell").text.strip).to be_empty
      expect(html).not_to include(released.name)
    end

    it_behaves_like "the signed-in rows of every response"
  end

  context "in a space with another name" do
    let!(:space) { create(:space, name: "MTC") }

    def check_rows(html)
      expect(Nokogiri::HTML(html).at_css("tr[data-user-id='#{visitor.id}']")).to be_present
      expect(printers_cells(html)).to be_empty
      expect(html).not_to include(um2p.name)
    end

    it_behaves_like "the signed-in rows of every response"
  end
end
