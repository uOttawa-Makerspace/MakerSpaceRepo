require "rails_helper"

RSpec.describe ProficientProjectsController, type: :controller do
  describe "#index" do
    context "index" do
      it "should show the index page" do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        get :index
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "#new" do
    context "new" do
      it "should show the new page" do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10_000
        get :new
        expect(response).to have_http_status(:success)
      end

      it "should redirect to development_programs_path" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        get :new
        expect(flash[:alert]).to eq("You must be a part of the Development Program to access this area.")
        expect(response).to redirect_to root_path
      end
    end
  end

  describe "#show" do
    context "show" do
      it "should show the project page (admin)" do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10_000
        create(:proficient_project, :with_files)
        get :show, params: { id: ProficientProject.last.id }
        expect(response).to have_http_status(:success)
      end

      it "should show the project page (granted user)" do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        OrderStatus.find_or_create_by(name: "Completed")
        create(:order_item, :awarded)

        project = ProficientProject.last

        # Create photo
        photo = project.photos.new(width: 100, height: 100)
        photo.image.attach(
          io: File.open(Rails.root.join("spec/support/assets/avatar.png")),
          filename: "avatar.png",
          content_type: "image/png"
        )
        photo.save!

        Order.last.update(user_id: user.id)
        get :show, params: { id: project.id }
        expect(response).to have_http_status(:success)
      end

      it "should deny access to user" do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        create(:proficient_project)
        get :show, params: { id: ProficientProject.last.id }
        expect(response).to redirect_to development_programs_path
        expect(flash[:alert]).to eq("You cannot access this area.")
      end
    end
  end

  describe "#create" do
    context "create" do
      before(:each) do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10_000
      end

      it "should create the proficient project" do
        pp_params = FactoryBot.attributes_for(:proficient_project)
        expect do
          post :create, params: { proficient_project: pp_params }
        end.to change(ProficientProject, :count).by(1)
        expect(flash[:notice]).to eq("Proficient Project successfully created.")
      end

      it "should create the proficient project with training requirements" do
        pp_params = FactoryBot.attributes_for(:proficient_project)
        training_1 = create(:training)
        training_2 = create(:training)
        expect do
          post :create,
               params: {
                 proficient_project: pp_params,
                 training_requirements_id: [training_1.id, training_2.id],
                 training_requirements_level: ["Beginner", "Intermediate"]
               }
        end.to change(ProficientProject, :count).by(1)
        expect(
          TrainingRequirement.where(
            proficient_project_id: ProficientProject.last.id
          ).count
        ).to eq(2)
        expect(flash[:notice]).to eq("Proficient Project successfully created.")
      end

      it "should create the proficient project with images and files" do
        pp_params = FactoryBot.attributes_for(:proficient_project)
        expect do
          post :create,
               params: {
                 proficient_project: pp_params,
                 files: [
                   fixture_file_upload(
                     Rails.root.join("spec/support/assets/RepoFile1.pdf"),
                     "application/pdf"
                   )
                 ],
                 images: [
                   fixture_file_upload(
                     Rails.root.join("spec/support/assets/avatar.png"),
                     "image/png"
                   )
                 ]
               }
        end.to change(ProficientProject, :count).by(1)
        expect(RepoFile.count).to eq(1)
        expect(Photo.count).to eq(1)
        expect(response.body).to redirect_to(
          proficient_project_path(ProficientProject.last.id)
        )
      end

      it "should fail to create the proficient project" do
        pp_params = FactoryBot.attributes_for(:proficient_project, :broken)
        expect do
          post :create, params: { proficient_project: pp_params }
        end.to change(ProficientProject, :count).by(0)
        expect(response).to have_http_status(:unprocessable_content)
        expect(flash[:alert]).to eq("Something went wrong")
      end
    end
  end

  describe "#destroy" do
    context "destroy" do
      it "should destroy the proficient project" do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10_000
        create(:proficient_project)
        expect do
          delete :destroy, params: { id: ProficientProject.last.id }
        end.to change(ProficientProject, :count).by(-1)
        expect(response).to redirect_to proficient_projects_path
        expect(flash[:notice]).to eq(
          "Proficient Project has been successfully deleted."
        )
      end
    end
  end

  describe "#edit" do
    context "edit" do
      it "should show the edit page" do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10_000
        create(:proficient_project)
        get :edit, params: { id: ProficientProject.last.id }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "#update" do
    context "update" do
      before(:each) do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10_000
      end

      it "should update the proficient project" do
        create(:proficient_project)
        patch :update,
              params: {
                id: ProficientProject.last.id,
                proficient_project: {
                  title: "abc"
                }
              }
        expect(response.body).to redirect_to(
          proficient_project_path(ProficientProject.last.id)
        )
        expect(flash[:notice]).to eq("Proficient Project successfully updated.")
      end

      it "should update the proficient project with badge requirements" do
        create(:proficient_project)
        patch :update,
              params: {
                id: ProficientProject.last.id,
                proficient_project: {
                  title: "abc"
                },
                training_requirements_id: [create(:training).id, create(:training).id],
                training_requirements_level: ["Beginner", "Intermediate"]
              }
        expect(response.body).to redirect_to(
          proficient_project_path(ProficientProject.last.id)
        )
        expect(
          TrainingRequirement.where(
            proficient_project_id: ProficientProject.last.id
          ).count
        ).to eq(2)
        expect(flash[:notice]).to eq("Proficient Project successfully updated.")
      end

      it "should update the proficient project with photos and files" do
        create(:proficient_project, :with_files)
        patch :update,
              params: {
                id: ProficientProject.last.id,
                proficient_project: {
                  title: "abc"
                },
                files: [
                  fixture_file_upload(
                    Rails.root.join("spec/support/assets/RepoFile1.pdf"),
                    "application/pdf"
                  )
                ],
                images: [
                  fixture_file_upload(
                    Rails.root.join("spec/support/assets/avatar.png"),
                    "image/png"
                  )
                ],
                deleteimages: [Photo.last.image.filename.to_s],
                deletefiles: [RepoFile.last.file.filename.to_s]
              }
        expect(response.body).to redirect_to(
          proficient_project_path(ProficientProject.last.id)
        )
        expect(RepoFile.count).to eq(1)
        expect(Photo.count).to eq(1)
        expect(flash[:notice]).to eq("Proficient Project successfully updated.")
      end

      it "should fail to update the proficient project" do
        create(:proficient_project)
        patch :update,
              params: {
                id: ProficientProject.last.id,
                proficient_project: {
                  title: ""
                }
              }
        expect(flash[:alert]).to eq("Unable to apply the changes.")
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "#open_modal" do
    context "open modal" do
      it "should open modal" do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        create(:proficient_project)
        get :proficient_project_modal,
            params: {
              proficient_project_id: ProficientProject.last.id
            }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "#complete_project" do
    context "complete_project" do
      it "should set the pp as Waiting for approval" do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        create(:order, :with_item, user_id: user.id)
        proficient_project = ProficientProject.last
        put :complete_project,
            format: "js",
            params: {
              id: proficient_project.id,
              order_item: {
                user_comments: "",
                files: []
              }
            }
        expect(response).to redirect_to proficient_project
        expect(proficient_project.order_items.last.status).to eq(
          "Waiting for approval"
        )
        expect(ActionMailer::Base.deliveries.count).to eq(2)
        expect(flash[:notice]).to eq(
          "Congratulations on submitting this proficient project! The proficient project will now be reviewed by an admin in around 5 business days."
        )
      end
    end
  end

  describe "#approve_project" do
    context "approve_project" do
      before(:each) do
        @user = create(:user, :admin)
        session[:user_id] = @user.id
        session[:expires_at] = Time.zone.now + 10_000
        create(:order, :with_item, user_id: @user.id)
        create(:user, email: "avend029@uottawa.ca")
        @proficient_project = ProficientProject.last
        put :complete_project,
            format: "js",
            params: {
              id: @proficient_project.id,
              order_item: {
                user_comments: "",
                files: []
              }
            }
      end

      it "should allow a staff member to approve the project" do
        staff = create(:user, :staff)
        session[:staff_id] = staff.id
        session[:expires_at] = Time.zone.now + 10_000
        get :approve_project,
            params: {
              oi_id: OrderItem.last.id,
              order_item: {
                admin_comments: ""
              }
            }
        expect(response).to redirect_to requests_proficient_projects_path
        expect(OrderItem.last.status).to eq("Awarded")
        expect(ActionMailer::Base.deliveries.count).to eq(3)
        # Unreliable test - Mailing orders aren't consistent
        #expect(ActionMailer::Base.deliveries.second.to.last).to eq(staff.email)
        expect(flash[:notice]).not_to be_nil
      end

      it "should set the oi as Awarded" do
        get :approve_project,
            params: {
              oi_id: OrderItem.last.id,
              order_item: {
                admin_comments: ""
              }
            }
        sleep 3
        expect(response).to redirect_to requests_proficient_projects_path
        expect(OrderItem.last.status).to eq("Awarded")
        expect(ActionMailer::Base.deliveries.count).to eq(3)
        expect(ActionMailer::Base.deliveries.second.to.first).to eq(@user.email)
        expect(flash[:notice]).not_to be_nil
      end

      it "should NOT set the oi as Awarded" do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        get :approve_project, format: "js"
        expect(response).to redirect_to development_programs_path
        expect(OrderItem.last.status).to eq("Waiting for approval")
        expect(flash[:alert]).to eq("Only staff members can access this area.")
      end

      it "should create a new Certification" do
        expect do
          get :approve_project,
            params: {
              oi_id: OrderItem.last.id,
              order_item: {
                admin_comments: ""
              }
            }
        end.to change(Certification, :count).by(1)
      end

      it "should NOT create a new Certification" do
        create(:certification, user: OrderItem.last.order.user, training: @proficient_project.training, 
level: @proficient_project.level)
        expect do
          get :approve_project,
            params: {
              oi_id: OrderItem.last.id,
              order_item: {
                admin_comments: ""
              }
            }
        end.to change(Certification, :count).by(0)
      end
    end
  end

  describe "#revoke_project" do
    context "revoke_project" do
      before(:each) do
        @user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = @user.id
        session[:expires_at] = Time.zone.now + 10_000
        create(:order, :with_item, user_id: @user.id)
        @proficient_project = ProficientProject.last
        put :complete_project,
            format: "js",
            params: {
              id: @proficient_project.id,
              order_item: {
                user_comments: "",
                files: []
              }
            }
      end

      it "should set the oi as Revoked" do
        get :revoke_project,
            format: "js",
            params: {
              oi_id: OrderItem.last.id,
              order_item: {
                admin_comments: ""
              }
            }
        expect(response).to redirect_to requests_proficient_projects_path
        expect(OrderItem.last.status).to eq("Revoked")
        expect(ActionMailer::Base.deliveries.count).to eq(3)
        expect(ActionMailer::Base.deliveries.second.to.first).to eq(@user.email)
        expect(flash[:alert_yellow]).to eq("The project has been revoked.")
      end

      it "should NOT set the oi as Revoked" do
        get :revoke_project, format: "js"
        expect(response).to redirect_to requests_proficient_projects_path
        expect(OrderItem.order(updated_at: :desc).first.status).to eq(
          "Waiting for approval"
        )
        expect(flash[:error]).to eq(
          "An error has occurred, please try again later."
        )
      end
    end
  end
end
