require "rails_helper"

RSpec.describe PrinterTypesController, type: :controller do
  before (:all) do
    @admin = create(:user, :admin)
    @staff = create(:user, :staff)
    @regular_user = create(:user, :regular_user)

    @um2p = create(:printer_type, :UM2P)
    @um3 = create(:printer_type, :UM3)
  end

  describe "#index" do
    context "logged in as regular user" do
      it "should redirect back to root" do
        session[:user_id] = @regular_user.id
        session[:expires_at] = Time.zone.now + 10_000

        get :index
        expect(response).to redirect_to(root_path)
      end
    end

    context "logged in as a staff" do
      it "should not show the printer models" do
        session[:user_id] = @staff.id
        session[:expires_at] = Time.zone.now + 10_000

        get :index
        expect(flash[:alert]).to eq("You cannot access this area")
      end
    end
  end

  describe "#create" do
    context "logged in as admin" do
      before(:each) do
        session[:user_id] = @admin.id
        session[:expires_at] = Time.zone.now + 10_000
      end

      it "should not create the printer type" do
        post :create, params: { printer_type: { name: "", short_form: "ABC" } }

        expect(flash[:alert]).to eq("Please input a printer model")
      end

      it "should create the printer type" do
        post :create,
             params: {
               printer_type: {
                 name: "New Model",
                 short_form: "NM"
               }
             }

        expect(flash[:notice]).to eq("Successfully created new printer model")
      end

      it "should not create the printer type since it is not unique" do
        post :create,
             params: {
               printer_type: {
                 name: "Ultimaker 3",
                 short_form: ""
               }
             }

        expect(flash[:alert]).to eq("Printer model already exists")
      end
    end
  end

  describe "#update" do
    context "logged in as staff" do
      before (:each) do
        session[:user_id] = @staff.id
        session[:expires_at] = Time.zone.now + 10_000

        @um2p_1 =
          create(:printer, printer_type_id: @um2p.id, number: "UM2P - 1")
        @um2p_2 =
          create(:printer, printer_type_id: @um2p.id, number: "UM2P - 2")
      end

      it "should not update the printer type" do
        patch :update,
              params: {
                id: @um2p.id,
                printer_type: {
                  name: "",
                  short_form: "UM2P"
                }
              }

        expect(flash[:alert]).to eq("You cannot access this area")
      end
    end

    context "logged in as admin" do
      before(:each) do
        session[:user_id] = @admin.id
        session[:expires_at] = Time.zone.now + 10_000

        @um2p_1 = create(:printer, printer_type_id: @um2p.id, number: "1")
        @um2p_2 = create(:printer, printer_type_id: @um2p.id, number: "2")
      end

      it "should update the printer type and its short form" do
        patch :update,
              params: {
                id: @um2p.id,
                printer_type: {
                  name: "Ultimaker 2+",
                  short_form: "UM2+"
                }
              }

        expect(flash[:notice]).to eq("Successfully updated printer model")
        expect(Printer.find(@um2p_1.id).name).to eq("UM2+ - 1")
        expect(Printer.find(@um2p_2.id).name).to eq("UM2+ - 2")
      end
    end
  end

  describe "#destroy" do
    context "logged in as staff" do
      before(:each) do
        session[:user_id] = @staff.id
        session[:expires_at] = Time.zone.now + 10_000
      end

      it "should not allow staff to delete printer types" do
        delete :destroy, params: { id: @um2p.id }

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("You cannot access this area")
      end
    end

    context "logged in as admin" do
      before(:each) do
        session[:user_id] = @admin.id
        session[:expires_at] = Time.zone.now + 10_000
      end

      it "should allow admins to delete printer types" do
        delete :destroy, params: { id: @um2p.id }

        expect(flash[:notice]).to eq("Successfully deleted printer model")
      end
    end
  end
end
