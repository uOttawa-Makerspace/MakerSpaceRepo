require "rails_helper"

# Chunk 15: PrinterTypesController. StaffAreaController gate first (guest ->
# login, regular -> root alert), then an admin-only gate: staff are sent
# back (root without referer) with "You cannot access this area".
RSpec.describe "Printer types", type: :request do
  let!(:type) { create(:printer_type, :UM2P) }

  describe "auth matrix" do
    it "sends guests to login" do
      get printer_types_path
      expect(response).to redirect_to(login_path(back_to: printer_types_path))
      post printer_types_path, params: { printer_type: { name: "X" } }
      expect(PrinterType.where(name: "X")).to be_empty
    end

    it "bounces a regular user to root with the staff-area alert" do
      sign_in_as(:regular)
      get printer_types_path
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You cannot access this area.")
    end

    it "bounces staff from every action with the admin alert and changes nothing" do
      sign_in_as(:staff)
      get printer_types_path
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You cannot access this area")
      get new_printer_type_path
      expect(response).to redirect_to(root_path)
      get edit_printer_type_path(type)
      expect(response).to redirect_to(root_path)
      expect { post printer_types_path, params: { printer_type: { name: "New" } } }.not_to change(PrinterType, :count)
      patch printer_type_path(type), params: { printer_type: { name: "Hacked" } }
      expect(type.reload.name).to eq("Ultimaker 2+")
      expect { delete printer_type_path(type) }.not_to change(PrinterType, :count)
    end

    it "redirects back to the referer when there is one" do
      sign_in_as(:staff)
      get printer_types_path, headers: { "HTTP_REFERER" => staff_printers_printers_url }
      expect(response).to redirect_to(staff_printers_printers_url)
    end
  end

  describe "as admin" do
    before { sign_in_as(:admin) }

    # N+1 pinned: see defects D-PERF-EQ03
    it "lists types ordered case-insensitively", skip_bullet: true do
      create(:printer_type, name: "apple", short_form: "A")
      get printer_types_path
      expect(response).to have_http_status(:ok)
      expect(response.body.index("apple")).to be < response.body.index("Ultimaker 2+")
    end

    it "renders new and edit" do
      get new_printer_type_path
      expect(response).to have_http_status(:ok)
      get edit_printer_type_path(type)
      expect(response).to have_http_status(:ok)
    end

    it "redirects edit of an unknown id to the index with an alert" do
      get edit_printer_type_path(0)
      expect(response).to redirect_to(printer_types_path)
      expect(flash[:alert]).to eq("Couldn't find Printer Model")
    end

    it "creates a type" do
      expect { post printer_types_path, params: { printer_type: { name: "Prusa", short_form: "PRU", available: "1" } } }.to change(PrinterType, :count).by(1)
      expect(response).to redirect_to(printer_types_path)
      expect(flash[:notice]).to eq("Successfully created new printer model")
      expect(PrinterType.find_by(name: "Prusa")).to have_attributes(short_form: "PRU", available: true)
    end

    it "alerts for a blank name and for a duplicate name" do
      post printer_types_path, params: { printer_type: { name: "" } }
      expect(response).to redirect_to(new_printer_type_path)
      expect(flash[:alert]).to eq("Please input a printer model")
      post printer_types_path, params: { printer_type: { name: "Ultimaker 2+" } }
      expect(response).to redirect_to(new_printer_type_path)
      expect(flash[:alert]).to eq("Printer model already exists")
    end

    it "updates a type" do
      patch printer_type_path(type), params: { printer_type: { name: "UM2 Plus", available: "0" } }
      expect(response).to redirect_to(printer_types_path)
      expect(flash[:notice]).to eq("Successfully updated printer model")
      expect(type.reload).to have_attributes(name: "UM2 Plus", available: false)
    end

    it "alerts when the update is invalid" do
      patch printer_type_path(type), params: { printer_type: { name: "" } }
      expect(flash[:alert]).to eq("Failed to update printer model")
      expect(type.reload.name).to eq("Ultimaker 2+")
    end

    # WART(D-EQ16): destroying a printer type cascades (dependent: :destroy) to its printers and their sessions without confirmation or guard
    it "destroys a type together with its printers and their sessions" do
      printer = create(:printer, printer_type: type, number: "1")
      create(:printer_session, printer: printer)
      expect { delete printer_type_path(type) }.to change(PrinterType, :count).by(-1).and change(Printer, :count).by(-1).and change(PrinterSession, :count).by(-1)
      expect(response).to redirect_to(printer_types_path)
      expect(flash[:notice]).to eq("Successfully deleted printer model")
    end

    it "redirects update/destroy of an unknown id with an alert" do
      delete printer_type_path(0)
      expect(response).to redirect_to(printer_types_path)
      expect(flash[:alert]).to eq("Couldn't find Printer Model")
    end
  end
end
