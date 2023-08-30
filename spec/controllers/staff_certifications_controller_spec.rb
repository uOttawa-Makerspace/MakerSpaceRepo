require "rails_helper"

RSpec.describe StaffCertificationsController, type: :controller do
  describe "create" do
    context "staff" do
      before(:each) do
        @user = create(:user, :staff)
        session[:user_id] = @user.id
        session[:expires_at] = Time.zone.now + 10_000
      end

      it "should create the staff certification" do
        post :create

        expect(response).to redirect_to user_path(@user.username)
        expect(flash[:notice]).to eql(
          "Successfully created staff certification"
        )
      end

      it "should not create more than one staff certification" do
        create(:staff_certification, user_id: @user.id)

        post :create
        expect(response).to redirect_to user_path(@user.username)
        expect(flash[:alert]).to eql(
          "You have already created a staff certification"
        )
      end
    end

    context "regular user" do
      it "should not allow regular users" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000

        post :create
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eql("You cannot access this area.")
      end
    end
  end

  describe "show" do
    context "staff" do
      before(:each) do
        @user = create(:user, :staff)
        session[:user_id] = @user.id
        session[:expires_at] = Time.zone.now + 10_000

        @other_user = create(:user, :staff)
      end

      it "should allow staff to view their own staff certification" do
        sc = create(:staff_certification, user_id: @user.id)

        get :show, params: { id: sc.id }
        expect(response).to have_http_status(:success)
      end

      it "should not allow staff to view other staff certifications" do
        sc = create(:staff_certification, user_id: @other_user.id)

        get :show, params: { id: sc.id }
        expect(response).to redirect_to users_path(@user.username)
        expect(flash[:alert]).to eql("You cannot access this page")
      end
    end

    context "admin" do
      it "should allow admins to access show page" do
        user = create(:user, :admin)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000

        other_user = create(:user, :staff)
        sc = create(:staff_certification, user_id: other_user.id)

        get :show, params: { id: sc.id }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "update" do
    context "staff" do
      it "should update the staff certification" do
        user = create(:user, :staff)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000

        sc = create(:staff_certification, user_id: user.id)
        pdf_file =
          fixture_file_upload(
            Rails.root.join("spec/support/assets", "RepoFile1.pdf"),
            "application/pdf"
          )
        patch :update, params: { id: sc.id, pdf_file_1: pdf_file }

        expect(flash[:notice]).to eql(
          "Successfully updated staff certifications"
        )
        expect(StaffCertification.last.get_staff_certs_attached).to eql(1)
      end
    end
  end

  describe "destroy_pdf" do
    context "staff" do
      it "should destroy individual pdfs" do
        user = create(:user, :staff)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000

        sc = create(:staff_certification, user_id: user.id)

        (1..StaffCertification::TOTAL_NUMBER_OF_FILES).each do |i|
          pdf_file =
            fixture_file_upload(
              Rails.root.join("spec/support/assets", "RepoFile1.pdf"),
              "application/pdf"
            )
          sc.send("pdf_file_#{i}").attach(pdf_file)
        end

        delete :destroy_pdf, params: { id: sc.id, file_number: 1 }

        expect(flash[:notice]).to eql("Successfully deleted certification")
        expect(StaffCertification.last.get_staff_certs_attached).to eql(
          StaffCertification::NUMBER_OF_STAFF_FILES - 1
        )
      end

      it "should not destroy unattached pdfs" do
        user = create(:user, :staff)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000

        sc = create(:staff_certification, user_id: user.id)
        delete :destroy_pdf, params: { id: sc.id, file_number: 1 }

        expect(flash[:alert]).to eql("Couldn't find attached file")
      end
    end
  end
end
