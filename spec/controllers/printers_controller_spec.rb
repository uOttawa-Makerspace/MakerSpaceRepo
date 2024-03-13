require "rails_helper"

RSpec.describe PrintersController, type: :controller do
  describe "POST /add_printer" do
    before(:all) { @printer_type = create(:printer_type, :UM2P) }

    context "add printer" do
      it "should add the printer" do
        post :add_printer,
             params: {
               printer: {
                 number: "UM2P-01"
               },
               model_id: PrinterType.first.id
             }
        expect(response).to redirect_to printers_path
        expect(flash[:notice]).to eq("Printer added successfully!")
      end

      it "should not add the printer" do
        post :add_printer,
             params: {
               printer: {
                 number: ""
               },
               model_id: PrinterType.first.id
             }
        expect(response).to redirect_to printers_path
        expect(flash[:alert]).to eq("Invalid printer model or number")
      end

      it "should not add the printer" do
        post :add_printer, params: { printer: { number: "UM2P-01" } }
        expect(response).to redirect_to printers_path
        expect(flash[:alert]).to eq("Invalid printer model or number")
      end

      it "should not add the printer" do
        post :add_printer, params: { printer: { number: "" }, model_id: "" }
        expect(response).to redirect_to printers_path
        expect(flash[:alert]).to eq("Invalid printer model or number")
      end
    end
  end

  describe "POST /remove_printer" do
    context "remove printer" do
      it "should remove the printer" do
        printer = Printer.create(number: "UM2P-01")
        post :remove_printer, params: { remove_printer: printer.id }
        expect(response).to redirect_to printers_path
        expect(flash[:notice]).to eq("Printer removed successfully!")
      end

      it "should not remove the printer" do
        post :remove_printer, params: { remove_printer: "" }
        expect(response).to redirect_to printers_path
        expect(flash[:alert]).to eq("Please select a Printer.")
      end
    end
  end

  describe "Link printer to user" do
    before(:all) do
      build :printer, :UM2P_01
      build :printer, :UM2P_02
      build :printer, :UM3_01
      build :printer, :RPL2_01
      build :printer, :RPL2_02
      build :printer, :dremel_10_17
    end

    context "Create a printer session" do
      it "should create a Printer Session" do
        create :user, :regular_user
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        patch :link_printer_to_user,
              params: {
                printer: {
                  user_id: 1,
                  printer_id: 1
                }
              }
        expect(flash[:notice]).to eq("Printer Session Created")
        expect(response).to redirect_to staff_printers_printers_path
      end

      it "should create deny access" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        patch :link_printer_to_user,
              params: {
                printer: {
                  user_id: 1,
                  printer_id: 1
                }
              }
        expect(flash[:alert]).to eq("You cannot access this area.")
        expect(response).to redirect_to "/"
      end

      it "should fail creating the print session" do
        create :user, :regular_user
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        patch :link_printer_to_user,
              params: {
                printer: {
                  user_id: 1,
                  printer_id: ""
                }
              }
        expect(flash[:alert]).to eq("Please add both printer and user.")
        expect(response).to redirect_to staff_printers_printers_path
      end
    end
  end

  describe "controllers that have views" do
    before(:each) do
      @um2_1 = create :printer, :UM2P_01
      @um2_2 = create :printer, :UM2P_02
      @um3 = create :printer, :UM3_01
      @rpl1 = create :printer, :RPL2_01
      @rpl2 = create :printer, :RPL2_02
      @dremel = create :printer, :dremel_10_17
    end

    context "Variable setup for views" do
      it "should setup all variables for staff_printers_updates" do
        create :user, :regular_user
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        get :staff_printers_updates
        expect(response).to have_http_status(:success)
      end

      it "should create all the variables for staff_printers" do
        create :user, :regular_user
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        um2p_session = create(:printer_session, printer_id: @um2_2.id)
        um3_session = create(:printer_session, printer_id: @um3.id)
        rpl2_session = create(:printer_session, printer_id: @rpl2.id)
        dremel_session = create(:printer_session, printer_id: @dremel.id)
        get :staff_printers
        expect(response).to have_http_status(:success)
      end
    end
  end
end
