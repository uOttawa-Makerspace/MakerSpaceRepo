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
      expect(response).to redirect_to(login_path)
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

    # The printer list in the remove form reads each printer's model.
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

    it "removes a printer that has no sessions or issues" do
      expect { post remove_printer_printers_path, params: { remove_printer: um2p.id } }.to change(Printer, :count).by(-1)
      expect(response).to redirect_to(printers_path)
      expect(flash[:notice]).to eq("Printer removed successfully!")
    end

    it "keeps a printer that has sessions, and its sessions, and says why" do
      create(:printer_session, printer: um2p)
      expect { post remove_printer_printers_path, params: { remove_printer: um2p.id } }.not_to change { [Printer.count, PrinterSession.count] }
      expect(flash[:notice]).to be_nil
      expect(flash[:alert]).to eq("The printer was not removed. This printer has sessions or issues and cannot be removed.")
    end

    it "keeps a printer that has printer issues, and its issues, and says why" do
      create(:printer_issue, printer: um2p)
      expect { post remove_printer_printers_path, params: { remove_printer: um2p.id } }.not_to change { [Printer.count, PrinterIssue.count] }
      expect(response).to redirect_to(printers_path)
      expect(flash[:alert]).to eq("The printer was not removed. This printer has sessions or issues and cannot be removed.")
    end

    it "alerts when no printer is selected for removal" do
      expect { post remove_printer_printers_path, params: { remove_printer: "" } }.not_to change(Printer, :count)
      expect(flash[:alert]).to eq("Please select a Printer.")
    end

    it "alerts that the printer no longer exists for an unknown printer id" do
      expect { post remove_printer_printers_path, params: { remove_printer: 0 } }.not_to change(Printer, :count)
      expect(flash[:notice]).to be_nil
      expect(flash[:alert]).to eq(I18n.t("errors.printers.printer_not_found"))
    end

    it "asks for a printer when the remove_printer param is missing" do
      expect { post remove_printer_printers_path }.not_to change(Printer, :count)
      expect(flash[:notice]).to be_nil
      expect(flash[:alert]).to eq("Please select a Printer.")
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

    it "answers not found for an unknown printer id" do
      sign_in_as(:staff)
      patch printer_path(0), params: { printer: { maintenance: true } }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "staff pages" do
    before { sign_in_as(:staff) }

    it "renders staff_printers and staff_printers_updates" do
      get staff_printers_printers_path
      expect(response).to have_http_status(:ok)
      get staff_printers_updates_printers_path
      expect(response).to have_http_status(:ok)
    end

    it "printer_data refuses a plain page request and returns nested JSON" do
      create(:printer_issue, printer: um2p)
      get printer_data_printers_path
      expect(response).to have_http_status(:not_acceptable)
      get printer_data_printers_path(format: :json)
      expect(response).to have_http_status(:ok)
      row = json.find { |t| t["id"] == um2p.printer_type_id }
      expect(row.keys).to match_array(%w[id name short_form available printers])
      expect(row["printers"]).to eq([{ "id" => um2p.id, "number" => "01", "maintenance" => false, "has_issues" => true }])
    end

    it "leaves out printers that have never had a session" do
      user = create(:user, :regular_user)
      PrinterSession.create!(printer: um3, user: user, in_use: true)
      get last_user_assigned_to_printer_printers_path
      expect(response).to have_http_status(:ok)
      expect(json).to eq(um3.id.to_s => { "id" => user.id, "username" => user.username, "name" => user.name })
    end

    it "leaves out a printer whose last session has no user" do
      PrinterSession.create!(printer: um2p, user: nil, in_use: false)
      get last_user_assigned_to_printer_printers_path
      expect(response).to have_http_status(:ok)
      expect(json).to eq({})
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

    # JSON replies are an object keyed by notice or alert; an alert answers 400
    it "creates an in_use session and replies 200 JSON" do
      expect { link(user.id) }.to change(PrinterSession, :count).by(1)
      expect(response).to have_http_status(:ok)
      expect(json).to eq("notice" => "Printer Session Created")
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
      expect(response).to have_http_status(:ok)
      expect(json).to eq("notice" => "Cleared the user.")
      expect(PrinterSession.last.in_use).to be false
    end

    it "400s with an alert when the user is blank" do
      link("")
      expect(response).to have_http_status(:bad_request)
      expect(json).to eq("alert" => "Please add both printer and user.")
    end

    it "refuses array values for printer and user ids without creating a session or running them as SQL" do
      user
      statements = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| statements << payload[:sql] }
      expect do
        patch link_printer_to_user_printers_path(format: :json), params: { printer: { printer_id: um2p.id, user_id: ["1=1"] } }
        expect(response).to have_http_status(:bad_request)
        expect(json).to eq("alert" => "Please add both printer and user.")
        patch link_printer_to_user_printers_path(format: :json), params: { printer: { printer_id: ["1=1"], user_id: user.id } }
        expect(response).to have_http_status(:bad_request)
        expect(json).to eq("alert" => "Please add both printer and user.")
      end.not_to change(PrinterSession, :count)
      expect(statements.grep(/WHERE \(1=1\)/)).to be_empty
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it "refuses hash values for printer and user ids" do
      expect do
        patch link_printer_to_user_printers_path(format: :json), params: { printer: { printer_id: um2p.id, user_id: { a: "1" } } }
      end.not_to change(PrinterSession, :count)
      expect(response).to have_http_status(:bad_request)
      expect(json).to eq("alert" => "Please add both printer and user.")
    end

    it "refuses an unknown printer or user with its own alert and creates nothing" do
      expect do
        patch link_printer_to_user_printers_path(format: :json), params: { printer: { printer_id: 0, user_id: user.id } }
        expect(response).to have_http_status(:bad_request)
        expect(json).to eq("alert" => I18n.t("errors.printers.printer_not_found"))
        link(0)
        expect(response).to have_http_status(:bad_request)
        expect(json).to eq("alert" => I18n.t("errors.printers.user_not_found"))
        patch link_printer_to_user_printers_path(format: :json), params: { printer: { printer_id: 0, user_id: "clear" } }
        expect(response).to have_http_status(:bad_request)
        expect(json).to eq("alert" => I18n.t("errors.printers.printer_not_found"))
      end.not_to change(PrinterSession, :count)
    end

    it "redirects HTML requests to the staff printers page" do
      link(user.id, format: :html)
      expect(response).to redirect_to(staff_printers_printers_path)
    end

    it "clearing a printer that has no session changes nothing and replies 200" do
      expect { link("clear") }.not_to change(PrinterSession, :count)
      expect(response).to have_http_status(:ok)
      expect(json).to eq("notice" => "Cleared the user.")
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

    # M74: the body is the print_failed template with its placeholders filled in
    it "puts the formatted print_failed template (owner, printer, staff notes) in the mail body" do
      JobOrderMessage.create!(name: "print_failed",
                              message: "Hi [PRINT_OWNER_NAME], your print on [PRINTER_NUMBER] failed. Staff notes: [STAFF_NOTES]")
      ActionMailer::Base.deliveries.clear
      send_msg
      body = ActionMailer::Base.deliveries.last.body.encoded
      expect(body).to include("Hi #{owner.name}, your print on #{um2p.name} failed.")
      expect(body).to include("Staff notes: Spaghetti")
    end

    it "uses the default print_failed text in the body when no template was customised" do
      ActionMailer::Base.deliveries.clear
      send_msg
      expect(ActionMailer::Base.deliveries.last.body.encoded).to include("Print failed")
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

    it "redirects to the staff printers page for an unknown or missing sent_from" do
      send_msg(from: "other")
      expect(response).to redirect_to(staff_printers_printers_url)
      send_msg(from: nil)
      expect(response).to redirect_to(staff_printers_printers_url)
    end
  end
end
