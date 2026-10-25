require "rails_helper"

# Chunk 15: PrintersController (StaffAreaController: guests -> login with
# back_to; regular users and volunteers -> root "You cannot access this area.").
# index/add_printer/remove_printer are additionally admin-only (staff get
# "You cannot access this area" via redirect_back).
RSpec.describe "Printers", type: :request do
  include ActiveJob::TestHelper

  let!(:um2p) { create(:printer, :UM2P_01) }
  let!(:um3) { create(:printer, :UM3_01) }

  def json
    JSON.parse(response.body)
  end

  STAFF_GET_PATHS = %i[
    staff_printers_printers_path
    staff_printers_updates_printers_path
    last_user_assigned_to_printer_printers_path
    printer_data_printers_path
  ].freeze

  describe "auth matrix for staff-area actions" do
    STAFF_GET_PATHS.each do |helper|
      it "#{helper}: guest goes to login with back_to" do
        get send(helper, format: :json)
        expect(response).to redirect_to(login_path(back_to: send(helper, format: :json)))
      end

      %i[regular volunteer].each do |role|
        it "#{helper}: #{role} is bounced to root with an alert" do
          sign_in_as(role)
          get send(helper, format: :json)
          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to eq("You cannot access this area.")
        end
      end
    end

    it "bounces guests and regular users from every write action" do
      patch printer_path(um2p), params: { printer: { maintenance: true } }
      expect(response).to redirect_to(login_path(back_to: printer_path(um2p)))
      patch link_printer_to_user_printers_path, params: { printer: { printer_id: um2p.id, user_id: "clear" } }
      expect(response).to have_http_status(:found)
      expect(PrinterSession.count).to eq(0)
      sign_in_as(:regular)
      patch printer_path(um2p), params: { printer: { maintenance: true } }
      expect(response).to redirect_to(root_path)
      expect(um2p.reload.maintenance).to be_falsey
      post add_printer_printers_path, params: { printer: { number: "9" }, model_id: um2p.printer_type_id }
      expect(response).to redirect_to(root_path)
      expect(Printer.where(number: "9")).to be_empty
    end
  end

  describe "admin-only actions as staff" do
    before { sign_in_as(:staff) }

    it "redirects index back (to root without referer) with an alert" do
      get printers_path
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You cannot access this area")
    end

    it "redirects add_printer and remove_printer, changing nothing" do
      expect { post add_printer_printers_path, params: { printer: { number: "7" }, model_id: um2p.printer_type_id } }.not_to change(Printer, :count)
      expect(flash[:alert]).to eq("You cannot access this area")
      expect { post remove_printer_printers_path, params: { remove_printer: um2p.id } }.not_to change(Printer, :count)
      expect(response).to redirect_to(root_path)
    end
  end

  describe "admin: index, add_printer, remove_printer" do
    before { sign_in_as(:admin) }

    # N+1 pinned: see defects D-PERF-EQ01
    it "renders index with printer models labelled with short forms", skip_bullet: true do
      get printers_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ultimaker 2+ (UM2P)")
    end

    it "adds a printer and redirects with the model preserved" do
      expect { post add_printer_printers_path, params: { printer: { number: "05" }, model_id: um2p.printer_type_id } }.to change(Printer, :count).by(1)
      expect(response).to redirect_to(printers_path(model_id: um2p.printer_type_id))
      expect(flash[:notice]).to eq("Printer added successfully!")
      expect(Printer.find_by(number: "05").printer_type_id).to eq(um2p.printer_type_id)
    end

    it "rejects a duplicate number for the same model" do
      expect { post add_printer_printers_path, params: { printer: { number: "01" }, model_id: um2p.printer_type_id } }.not_to change(Printer, :count)
      expect(flash[:alert]).to eq("Printer number already exists")
    end

    it "rejects a blank number or model" do
      post add_printer_printers_path, params: { printer: { number: "" }, model_id: um2p.printer_type_id }
      expect(flash[:alert]).to eq("Invalid printer model or number")
      post add_printer_printers_path, params: { printer: { number: "3" }, model_id: "" }
      expect(flash[:alert]).to eq("Invalid printer model or number")
      expect(response).to redirect_to(printers_path)
    end

    it "removes a printer (and its sessions)" do
      create(:printer_session, printer: um2p)
      expect { post remove_printer_printers_path, params: { remove_printer: um2p.id } }.to change(Printer, :count).by(-1).and change(PrinterSession, :count).by(-1)
      expect(flash[:notice]).to eq("Printer removed successfully!")
    end

    it "500s removing a printer that has printer issues (FK violation, see D-EQ29)" do
      create(:printer_issue, printer: um2p)
      expect { post remove_printer_printers_path, params: { remove_printer: um2p.id } }.not_to change(Printer, :count)
      expect(response).to have_http_status(:internal_server_error)
    end

    it "alerts when no printer is selected for removal" do
      expect { post remove_printer_printers_path, params: { remove_printer: "" } }.not_to change(Printer, :count)
      expect(flash[:alert]).to eq("Please select a Printer.")
    end

    # WART(D-EQ09): remove_printer reports success for an unknown id (destroy_all on an empty relation)
    it "reports success even for an unknown printer id" do
      post remove_printer_printers_path, params: { remove_printer: 0 }
      expect(flash[:notice]).to eq("Printer removed successfully!")
    end

    # WART(D-EQ10): remove_printer with no remove_printer param (nil != "") runs destroy_all on where(id: nil), a silent no-op reported as success
    it "treats a missing remove_printer param as a successful removal" do
      expect { post remove_printer_printers_path }.not_to change(Printer, :count)
      expect(flash[:notice]).to eq("Printer removed successfully!")
    end
  end

  describe "PATCH /printers/:id" do
    it "lets staff change maintenance but not the number" do
      sign_in_as(:staff)
      patch printer_path(um2p), params: { printer: { maintenance: true, number: "99" } }, headers: { "HTTP_REFERER" => staff_printers_printers_url }
      expect(response).to redirect_to(staff_printers_printers_url)
      expect(flash[:notice]).to eq("Printer #{um2p.name} updated")
      expect(um2p.reload).to have_attributes(maintenance: true, number: "01")
    end

    it "lets an admin change the number as well" do
      sign_in_as(:admin)
      patch printer_path(um2p), params: { printer: { number: "42" } }
      expect(response).to redirect_to(printers_path)
      expect(um2p.reload.number).to eq("42")
    end

    it "alerts when validation fails (blank number, admin)" do
      sign_in_as(:admin)
      patch printer_path(um2p), params: { printer: { number: "" } }
      expect(flash[:alert]).to eq("Failed to update printer")
      expect(um2p.reload.number).to eq("01")
    end

    # WART(D-EQ11): update uses find_by(...).update so an unknown printer id raises NoMethodError (500) instead of 404
    it "500s for an unknown printer id" do
      sign_in_as(:staff)
      patch printer_path(0), params: { printer: { maintenance: true } }
      expect(response).to have_http_status(:internal_server_error)
    end
  end

  describe "staff pages" do
    before { sign_in_as(:staff) }

    # N+1 pinned: see defects D-PERF-EQ02
    it "renders staff_printers and staff_printers_updates", skip_bullet: true do
      get staff_printers_printers_path
      expect(response).to have_http_status(:ok)
      get staff_printers_updates_printers_path
      expect(response).to have_http_status(:ok)
    end

    it "printer_data redirects HTML to root and returns nested JSON" do
      create(:printer_issue, printer: um2p)
      get printer_data_printers_path
      expect(response).to redirect_to(root_path)
      get printer_data_printers_path(format: :json)
      expect(response).to have_http_status(:ok)
      row = json.find { |t| t["id"] == um2p.printer_type_id }
      expect(row.keys).to match_array(%w[id name short_form available printers])
      expect(row["printers"]).to eq([{ "id" => um2p.id, "number" => "01", "maintenance" => false, "has_issues" => true }])
    end

    # WART(D-EQ12): last_user_assigned_to_printer raises NoMethodError (500) as soon as any printer has no session
    it "500s when a printer has never had a session" do
      get last_user_assigned_to_printer_printers_path
      expect(response).to have_http_status(:internal_server_error)
    end

    it "maps printer ids to the last session user when every printer has one" do
      u1 = create(:user, :regular_user)
      u2 = create(:user, :regular_user)
      PrinterSession.create!(printer: um2p, user: u1, in_use: true)
      PrinterSession.create!(printer: um2p, user: u2, in_use: true)
      PrinterSession.create!(printer: um3, user: u1, in_use: true)
      get last_user_assigned_to_printer_printers_path
      expect(json).to eq(
        um2p.id.to_s => { "id" => u2.id, "username" => u2.username, "name" => u2.name },
        um3.id.to_s => { "id" => u1.id, "username" => u1.username, "name" => u1.name }
      )
    end
  end

  describe "PATCH link_printer_to_user" do
    let(:user) { create(:user, :regular_user) }
    before { sign_in_as(:staff) }

    def link(user_id, format: :json)
      patch link_printer_to_user_printers_path(format: format), params: { printer: { printer_id: um2p.id, user_id: user_id } }
    end

    # WART(D-EQ15): link_printer_to_user renders the FlashHash as JSON, which serialises as an array of [key, message] pairs rather than an object
    it "creates an in_use session and replies 200 JSON" do
      expect { link(user.id) }.to change(PrinterSession, :count).by(1)
      expect(response).to have_http_status(:ok)
      expect(json).to eq([["notice", "Printer Session Created"]])
      expect(PrinterSession.last).to have_attributes(printer_id: um2p.id, user_id: user.id, in_use: true)
    end

    it "closes the previous in_use session when a new user is linked" do
      link(user.id)
      other = create(:user, :regular_user)
      link(other.id)
      expect(PrinterSession.where(printer: um2p).order(:id).pluck(:in_use)).to eq([false, true])
    end

    it "clears the current user" do
      link(user.id)
      link("clear")
      expect(json).to eq([["notice", "Cleared the user."]])
      expect(PrinterSession.last.in_use).to be false
    end

    it "400s with an alert when the user is blank" do
      link("")
      expect(response).to have_http_status(:bad_request)
      expect(json).to eq([["alert", "Please add both printer and user."]])
    end

    it "redirects HTML requests to the staff printers page" do
      link(user.id, format: :html)
      expect(response).to redirect_to(staff_printers_printers_path)
    end

    # WART(D-EQ13): clearing a printer that never had a session raises NoMethodError (500) because last_session is nil
    it "500s when clearing a printer that has no session" do
      link("clear")
      expect(response).to have_http_status(:internal_server_error)
    end
  end

  describe "PATCH send_print_failed_message_to_user" do
    let(:owner) { create(:user, :regular_user) }
    before { sign_in_as(:staff) }

    def send_msg(printer_id: um2p.id, username: owner.username, from: "printers")
      patch send_print_failed_message_to_user_printers_path,
            params: { print_failed_message: { printer_number: printer_id, username: username, staff_notes: "Spaghetti", sent_from: from } }
    end

    it "delivers the failure email to the print owner and redirects to staff printers" do
      ActionMailer::Base.deliveries.clear
      send_msg
      expect(response).to redirect_to(staff_printers_printers_url)
      expect(flash[:notice]).to eq("Email sent successfully")
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([owner.email])
      expect(mail.bcc).to eq(["uottawa.makerepo@gmail.com"])
      expect(mail.subject).to eq("Your 3D print on #{um2p.number} has failed")
    end

    it "redirects to the updates page when sent from there" do
      send_msg(from: "updates")
      expect(response).to redirect_to(staff_printers_updates_printers_url)
    end

    it "alerts for an unknown printer or username without sending mail" do
      ActionMailer::Base.deliveries.clear
      send_msg(printer_id: 0)
      expect(flash[:alert]).to eq("Error sending message, printer not found")
      send_msg(username: "ghost")
      expect(flash[:alert]).to eq("Error sending message, username not found")
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    # WART(D-EQ14): with an unrecognised sent_from nothing is rendered or redirected (implicit missing template, 204/500)
    it "has no response branch for an unknown sent_from" do
      send_msg(from: "other")
      expect(response.status).to be_in([204, 500])
    end
  end
end
