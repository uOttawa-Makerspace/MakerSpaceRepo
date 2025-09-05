require "rails_helper"

RSpec.describe PrintersController, type: :controller do
  before(:each) do
    session[:expires_at] = Time.zone.now + 10_000
  end

  describe "POST /printer" do
    before(:each) do
      @printer = create(:printer, :UM2P_01)
      @staff = create :user, :staff
      @admin = create :user, :admin
    end

    context "Update printer records" do
      it "should allow staff to set maintenance flag" do
        session[:user_id] = @staff.id
        post :update,
             params: {
               id: @printer.id,
               printer: {
                 maintenance: true
               }
             }
        expect(response).to redirect_to printers_path
        expect(Printer.find_by_id(@printer.id).maintenance).to eq(true)
      end

      it "should not allow staff to change numbers" do
        session[:user_id] = @staff.id
        post :update,
             params: {
               id: @printer.id,
               printer: {
                 number: "1234",
                 maintenance: true
               }
             }
        expect(response).to redirect_to printers_path
        expect(Printer.find_by_id(@printer.id).maintenance).to eq(true)
        expect(Printer.find_by_id(@printer.id).number).to eq(@printer.number)
        expect(Printer.find_by_id(@printer.id).number).to_not eq("1234")
      end

      it "should allow admin to change numbers and maintenance flag" do
        session[:user_id] = @admin.id
        post :update,
             params: {
               id: @printer.id,
               printer: {
                 number: "1234",
                 maintenance: true
               }
             }
        expect(response).to redirect_to printers_path
        expect(Printer.find_by_id(@printer.id).maintenance).to eq(true)
        expect(Printer.find_by_id(@printer.id).number).to eq("1234")
      end
    end
  end

  describe "POST /add_printer" do
    before(:each) do
      @printer_type = create(:printer_type, :Random)
      admin = create(:user, :admin)
      session[:user_id] = admin.id
      session[:expires_at] = Time.zone.now + 10_000
    end

    context "add printer" do
      it "should add the printer" do
        post :add_printer,
             params: {
               printer: {
                 number: "UM2P-01"
               },
               model_id: @printer_type.id
             }
        expect(response).to redirect_to printers_path(
                      model_id: @printer_type.id
                    )
        expect(flash[:notice]).to eq("Printer added successfully!")
      end

      it "should not add the printer" do
        post :add_printer,
             params: {
               printer: {
                 number: ""
               },
               model_id: @printer_type.id
             }
        expect(response).to redirect_to printers_path(
                      model_id: @printer_type.id
                    )
        expect(flash[:alert]).to eq("Invalid printer model or number")
      end

      it "should not add the printer" do
        post :add_printer, params: { printer: { number: "UM2P-01" } }
        expect(response).to redirect_to printers_path
        expect(flash[:alert]).to eq("Invalid printer model or number")
      end

      it "should not add the printer and not set model id" do
        post :add_printer, params: { printer: { number: "" }, model_id: "" }
        expect(response).to redirect_to printers_path
        expect(flash[:alert]).to eq("Invalid printer model or number")
      end
    end
  end

  describe "POST /remove_printer" do
    before(:each) do
      admin = create(:user, :admin)
      session[:user_id] = admin.id
      session[:expires_at] = Time.zone.now + 10_000
    end

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

  describe "Send print failed emails to print owners" do
    before(:all) { @printer = create :printer, :UM2P_01 }
    before(:each) do
      @print_owner = create :user, :regular_user
      staff = create :user, :staff
      session[:user_id] = staff.id
    end

    context "Send email to regular user as staff member" do
      it "should send email to user's email" do
        patch :send_print_failed_message_to_user,
              params: {
                print_failed_message: {
                  username: @print_owner.username,
                  printer_number: @printer.id,
                  staff_notes: "Testing staff notes."
                }
              }
        expect(flash[:alert]).to be_nil
        expect(flash[:notice]).to eq("Email sent successfully")
        expect(response).to have_http_status(:no_content)
      end

      it "should fail on unknown printers" do
        patch :send_print_failed_message_to_user,
              params: {
                print_failed_message: {
                  username: @print_owner.username,
                  printer_number: 515, # fake id
                  staff_notes: "Testing staff notes."
                }
              }
        expect(flash[:notice]).to be_nil
        expect(flash[:alert]).to eq("Error sending message, printer not found")
        expect(response).to have_http_status(:no_content)
      end

      it "should fail on unknown users" do
        patch :send_print_failed_message_to_user,
              params: {
                print_failed_message: {
                  username: "fakename",
                  printer_number: @printer.id, # fake id
                  staff_notes: "Testing staff notes."
                }
              }
        expect(flash[:notice]).to be_nil
        expect(flash[:alert]).to eq("Error sending message, username not found")
        expect(response).to have_http_status(:no_content)
      end
    end
  end
end
