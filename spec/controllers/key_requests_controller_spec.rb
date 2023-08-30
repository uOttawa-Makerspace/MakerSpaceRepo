require "rails_helper"

RSpec.describe KeyRequestsController, type: :controller do
  describe "index" do
    context "staff" do
      before(:each) do
        @space = create(:space)
        @admin = create(:user, :admin)
        @user = create(:user, :staff)
        session[:user_id] = @user.id
        session[:expires_at] = Time.zone.now + 10_000
      end

      it "should redirect to new key request form" do
        get :index
        expect(response).to redirect_to new_key_request_path
      end

      it "should redirect to steps form" do
        create(
          :key_request,
          :status_in_progress,
          user_id: @user.id,
          supervisor_id: @admin.id,
          space_id: @space.id
        )

        get :index
        expect(response).to redirect_to key_request_steps_path(
                      key_request_id: KeyRequest.last.id,
                      step: 1
                    )
      end

      it "should redirect to key request show page" do
        create(
          :key_request,
          :status_waiting_for_approval,
          :all_questions_answered,
          user_id: @user.id,
          supervisor_id: @admin.id,
          space_id: @space.id
        )

        get :index
        expect(response).to redirect_to key_request_path(KeyRequest.last.id)
      end
    end

    context "regular_user" do
      it "should redirect to home page" do
        @user = create(:user, :regular_user)
        session[:user_id] = @user.id
        session[:expires_at] = Time.zone.now + 10_000

        get :index
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq("You cannot access this area.")
      end
    end
  end

  describe "create" do
    before(:each) do
      @admin = create(:user, :admin)
      @staff = create(:user, :staff)
      @space = create(:space)

      session[:user_id] = @staff.id
      session[:expires_at] = Time.zone.now
    end

    context "admin" do
      it "should create the key request" do
        post :create,
             params: {
               key_request: {
                 student_number: 111_111_111,
                 phone_number: 1_111_111_111,
                 emergency_contact: "John Doe",
                 emergency_contact_phone_number: 2_222_222_222,
                 space_id: @space.id,
                 user_status: :student,
                 supervisor_id: @admin.id
               }
             }

        expect(KeyRequest.last.user.id).to eq(@staff.id)
        expect(KeyRequest.last.status).to eq("in_progress")
        expect(response).to redirect_to key_request_steps_path(
                      key_request_id: KeyRequest.last.id,
                      step: 2
                    )
      end

      it "should not create the key request" do
        post :create,
             params: {
               key_request: {
                 phone_number: 1_111_111_111,
                 emergency_contact: "John Doe",
                 emergency_contact_phone_number: 2_222_222_222,
                 space_id: @space.id,
                 user_status: :student,
                 supervisor_id: @admin.id
               }
             }

        expect(KeyRequest.count).to eq(0)
        expect(flash[:alert]).to eq(
          "Something went wrong while trying to submit the form."
        )
      end
    end
  end

  describe "show" do
    context "staff" do
      before(:each) do
        @staff = create(:user, :staff)
        @admin = create(:user, :admin)
        @space = create(:space)
      end

      it "should redirect to the show page if it's the staff's key request" do
        kr =
          create(
            :key_request,
            :status_waiting_for_approval,
            :all_questions_answered,
            user_id: @staff.id,
            supervisor_id: @admin.id,
            space_id: @space.id
          )

        session[:user_id] = @staff.id
        session[:expires_at] = Time.zone.now + 10_000

        get :show, params: { id: kr.id }
        expect(response).to have_http_status(:success)
      end

      it "should not redirect to the show page" do
        kr =
          create(
            :key_request,
            :status_waiting_for_approval,
            :all_questions_answered,
            user_id: @staff.id,
            supervisor_id: @admin.id,
            space_id: @space.id
          )
        other_staff = create(:user, :staff)

        session[:user_id] = other_staff.id
        session[:expires_at] = Time.zone.now + 10_000

        get :show, params: { id: kr.id }
        expect(flash[:alert]).to eq(
          "You don't have the permissions to view this"
        )
      end
    end

    context "admin" do
      it "should redirect to the show page" do
        user = create(:user, :admin)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000

        space = create(:space)
        staff = create(:user, :staff)
        kr =
          create(
            :key_request,
            :status_waiting_for_approval,
            :all_questions_answered,
            user_id: staff.id,
            supervisor_id: user.id,
            space_id: space.id
          )

        get :show, params: { id: kr.id }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "steps" do
    context "owner accessing their key request" do
      before(:each) do
        @staff = create(:user, :staff)
        @admin = create(:user, :admin)
        @space = create(:space)

        session[:user_id] = @staff.id
        session[:expires_at] = Time.zone.now + 10_000
      end

      it "should go to step 2" do
        kr =
          create(
            :key_request,
            :status_in_progress,
            user_id: @staff.id,
            supervisor_id: @admin.id,
            space_id: @space.id
          )
        other_space = create(:space)

        patch :steps,
              params: {
                step: 2,
                key_request_id: kr.id,
                key_request: {
                  student_number: 111_111_111,
                  phone_number: 1_111_111_111,
                  emergency_contact: "John Doe",
                  emergency_contact_phone_number: 2_222_222_222,
                  space_id: other_space.id,
                  user_status: :student,
                  supervisor_id: @admin.id
                }
              }

        expect(KeyRequest.last.space.id).to eq(other_space.id)
        expect(response).to render_template("lab_rules")
      end

      it "should go to step 3" do
        kr =
          create(
            :key_request,
            :status_in_progress,
            user_id: @staff.id,
            supervisor_id: @admin.id,
            space_id: @space.id
          )

        patch :steps,
              params: {
                step: 3,
                key_request_id: kr.id,
                key_request: {
                  read_lab_rules: "true"
                }
              }

        expect(KeyRequest.last.read_lab_rules).to eq(true)
        expect(response).to render_template("safety_questionnaire")
      end

      it "should go to step 4" do
        kr =
          create(
            :key_request,
            :status_in_progress,
            user_id: @staff.id,
            supervisor_id: @admin.id,
            space_id: @space.id
          )
        question_responses = Hash.new
        (1..KeyRequest::NUMBER_OF_QUESTIONS).each do |i|
          question_responses["question_#{i}"] = "response #{i}"
        end

        patch :steps,
              params: {
                step: 4,
                key_request_id: kr.id,
                key_request: question_responses
              }

        expect(response).to render_template("policies")
      end

      it "should go to step 5" do
        kr =
          create(
            :key_request,
            :status_in_progress,
            user_id: @staff.id,
            supervisor_id: @admin.id,
            space_id: @space.id
          )

        patch :steps,
              params: {
                step: 5,
                key_request_id: kr.id,
                key_request: {
                  read_policies: "true"
                }
              }

        expect(KeyRequest.last.read_policies).to eq(true)
        expect(response).to render_template("agreement")
      end

      it "should submit the key request" do
        kr =
          create(
            :key_request,
            :status_in_progress,
            :all_questions_answered,
            user_id: @staff.id,
            supervisor_id: @admin.id,
            space_id: @space.id,
            student_number: 111_111_111,
            phone_number: 1_111_111_111,
            emergency_contact: "John Doe",
            emergency_contact_phone_number: 2_222_222_222,
            user_status: :student,
            read_policies: true,
            read_lab_rules: true
          )

        patch :steps,
              params: {
                step: 6,
                key_request_id: kr.id,
                key_request: {
                  read_agreement: "true"
                }
              }

        expect(KeyRequest.last.read_agreement).to eq(true)
        expect(KeyRequest.last.status).to eq("waiting_for_approval")
        expect(flash[:notice]).to eq(
          "You have successfully submitted the key request form, please wait a few days for an admin to review your form."
        )
      end
    end

    context "another user accessing another key request" do
      it "should redirect to the staff dashboard page" do
        staff = create(:user, :staff)
        other_staff = create(:user, :staff)
        admin = create(:user, :admin)
        space = create(:space)

        kr =
          create(
            :key_request,
            :approved,
            :all_questions_answered,
            user_id: staff.id,
            supervisor_id: admin.id,
            space_id: space.id
          )

        session[:user_id] = other_staff.id
        session[:expires_at] = Time.zone.now + 10_000

        get :steps, params: { step: 1, key_request_id: kr.id }
        expect(flash[:alert]).to eq(
          "You don't have the permission to edit this key request."
        )
        expect(response).to redirect_to staff_dashboard_index_path
      end
    end
  end
end
