require "rails_helper"

RSpec.describe RepositoriesController, type: :controller do
  describe "#show" do
    context "show" do
      before(:each) do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
      end

      it "should show the repo (no password)" do
        create(:repository)
        get :show,
            params: {
              id: Repository.last.id,
              user_username: Repository.last.user_username
            }
        expect(response).to have_http_status(:success)
      end

      it "should show the repo (authenticated)" do
        create(:repository, :private)
        post :pass_authenticate,
             params: {
               user_username: Repository.last.user_username,
               id: Repository.last.id,
               password: "abc"
             }
        expect(response).to redirect_to repository_path(
                      Repository.last.user_username,
                      Repository.last.slug
                    )
        expect(flash[:notice]).to eq("Success")
      end

      it "should redirect user to the password form" do
        create(:repository, :private)
        get :show,
            params: {
              id: Repository.last.id,
              user_username: Repository.last.user_username
            }
        expect(response).to redirect_to password_entry_repository_path(
                      Repository.last.user_username,
                      Repository.last.id
                    )
      end
    end
  end

  describe "#download_files" do
    context "Download ZIP" do
      it "should create the zip" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        create(:repository, :with_repo_files)

        expect(@controller).to receive(:send_data) {
          @controller.render plain: "OK" # to prevent a 'missing template' error
        }

        get :download_files,
            params: {
              id: Repository.last.id,
              user_username: Repository.last.user_username
            }
      end
    end
  end

  describe "#new" do
    context "new" do
      it "should show the new page" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        get :new, params: { user_username: User.last.username }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "#edit" do
    context "edit" do
      it "should redirect the user" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        create(:repository)
        get :edit,
            params: {
              user_username: User.last.username,
              id: Repository.last.id
            }
        expect(response).to redirect_to repository_path(
                      Repository.last.user_username,
                      Repository.last.slug
                    )
        expect(flash[:alert]).to eq(
          "You are not allowed to perform this action!"
        )
      end

      it "should show the edit page" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        create(:repository)
        Repository.last.users << User.last
        get :edit,
            params: {
              user_username: User.last.username,
              id: Repository.last.id
            }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "#create" do
    context "create" do
      before(:each) do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
      end

      it "should create a repository" do
        repo_params = FactoryBot.attributes_for(:repository)
        expect {
          post :create,
               params: {
                 user_username: User.last.username,
                 repository: repo_params
               }
        }.to change(Repository, :count).by(1)
        expect(Repository.last.users.first.id).to eq(User.last.id)
        expect(User.last.reputation).to eq(25)
        expect(response.body).to include(
          repository_path(
            Repository.last.user_username,
            Repository.last.id
          ).to_s
        )
      end

      it "should create a repository with images and files" do
        repo_params = FactoryBot.attributes_for(:repository)
        expect {
          post :create,
               params: {
                 user_username: User.last.username,
                 repository: repo_params,
                 files: [
                   fixture_file_upload(
                     Rails.root.join("spec/support/assets", "RepoFile1.pdf"),
                     "application/pdf"
                   )
                 ],
                 images: [
                   fixture_file_upload(
                     Rails.root.join("spec/support/assets", "avatar.png"),
                     "image/png"
                   )
                 ]
               }
        }.to change(Repository, :count).by(1)
        expect(Repository.last.users.first.id).to eq(User.last.id)
        expect(User.last.reputation).to eq(25)
        expect(RepoFile.count).to eq(1)
        expect(Photo.count).to eq(1)
        expect(response.body).to include(
          repository_path(
            Repository.last.user_username,
            Repository.last.id
          ).to_s
        )
      end

      it "should create a repository with categories and equipements" do
        repo_params = FactoryBot.attributes_for(:repository)
        repo_params[:categories] = ["Laser", "3D Printing"]
        repo_params[:equipments] = ["Laser Cutter", "3D Printer"]
        expect {
          post :create,
               params: {
                 user_username: User.last.username,
                 repository: repo_params
               }
        }.to change(Repository, :count).by(1)
        expect(Repository.last.users.first.id).to eq(User.last.id)
        expect(User.last.reputation).to eq(25)
        expect(Repository.last.categories.count).to eq(2)
        expect(Repository.last.equipments.count).to eq(2)
        expect(response.body).to include(
          repository_path(
            Repository.last.user_username,
            Repository.last.id
          ).to_s
        )
      end

      it "should create a private repository" do
        repo_params = FactoryBot.attributes_for(:repository, :private)
        expect {
          post :create,
               params: {
                 user_username: User.last.username,
                 repository: repo_params
               }
        }.to change(Repository, :count).by(1)
        expect(Repository.last.users.first.id).to eq(User.last.id)
        expect(User.last.reputation).to eq(25)
        expect(Repository.last.password).not_to be_nil
        expect(response.body).to include(
          repository_path(
            Repository.last.user_username,
            Repository.last.slug
          ).to_s
        )
      end
    end
  end

  describe "#update" do
    context "update" do
      before(:each) do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
      end

      it "should update the repository" do
        create(:repository)
        patch :update,
              params: {
                user_username: User.last.username,
                id: Repository.last.id,
                repository: {
                  title: "abc"
                }
              }
        expect(response.body).to include(
          repository_path(
            Repository.last.user_username,
            Repository.last.id
          ).to_s
        )
        expect(flash[:notice]).to eq("Project updated successfully!")
      end

      it "should update the repository with photos and files" do
        create(:repository, :with_repo_files)
        patch :update,
              params: {
                user_username: User.last.username,
                id: Repository.last.id,
                repository: {
                  title: "abc"
                },
                files: [
                  fixture_file_upload(
                    Rails.root.join("spec/support/assets", "RepoFile1.pdf"),
                    "application/pdf"
                  )
                ],
                images: [
                  fixture_file_upload(
                    Rails.root.join("spec/support/assets", "avatar.png"),
                    "image/png"
                  )
                ],
                deleteimages: [Photo.last.image.filename.to_s],
                deletefiles: [RepoFile.last.file.id.to_s]
              }
        expect(response.body).to include(
          repository_path(
            Repository.last.user_username,
            Repository.last.id
          ).to_s
        )
        expect(RepoFile.count).to eq(1)
        expect(Photo.count).to eq(1)
        expect(flash[:notice]).to eq("Project updated successfully!")
      end

      it "should create a private repository" do
        create(:repository, :private)
        old_pass = Repository.last.password
        patch :update,
              params: {
                user_username: User.last.username,
                id: Repository.last.id,
                password: ["abcd"],
                repository: {
                  title: "abc"
                }
              }
        expect(response.body).to include(
          repository_path(
            Repository.last.user_username,
            Repository.last.id
          ).to_s
        )
        expect(Repository.last.password).not_to eq(old_pass)
        expect(
          BCrypt::Password.new(Repository.last.password) == "abcd"
        ).to be_truthy
        expect(flash[:notice]).to eq("Project updated successfully!")
      end
    end
  end

  describe "#destroy" do
    context "destroy" do
      it "should delete the repository" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        create(:repository)
        expect {
          delete :destroy,
                 params: {
                   user_username: User.last.username,
                   id: Repository.last.id
                 }
        }.to change(Repository, :count).by(-1)
      end
    end
  end

  describe "#add_like" do
    context "Add Like" do
      it "should add a like" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        create(:repository, user_id: user.id)
        Repository.last.users << User.last
        expect {
          post :add_like,
               params: {
                 user_username: User.last.username,
                 id: Repository.last.id
               }
        }.to change(Repository.last.likes, :count).by(1)
        expect(User.last.reputation).to eq(5)
      end

      it "should fail to add a second like from the same user" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        create(:repository, user_id: user.id)
        Repository.last.users << User.last
        expect {
          post :add_like,
               params: {
                 user_username: User.last.username,
                 id: Repository.last.id
               }
        }.to change(Repository.last.likes, :count).by(1)
        expect {
          post :add_like,
               params: {
                 user_username: User.last.username,
                 id: Repository.last.id
               }
        }.to change(Repository.last.likes, :count).by(0)
        expect(response.body).to include("failed")
      end
    end
  end

  describe "#password_entry" do
    context "password_entry" do
      it "should get the password page" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        create(:repository, :private)
        get :password_entry,
            params: {
              user_username: User.last.username,
              id: Repository.last.id
            }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "#pass_authenticate" do
    context "pass_authenticate" do
      it "should go back to the password page" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        create(:repository, :private)
        get :pass_authenticate,
            params: {
              user_username: User.last.username,
              id: Repository.last.id,
              password: ""
            }
        expect(response).to redirect_to password_entry_repository_path(
                      Repository.last.user_username,
                      Repository.last.slug
                    )
        expect(flash[:alert]).to eq("Incorrect password. Try again!")
      end

      it "should go to the authenticate user and go the repo page" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        create(:repository, :private)
        get :pass_authenticate,
            params: {
              user_username: User.last.username,
              id: Repository.last.id,
              password: "abc"
            }
        expect(response).to redirect_to repository_path(
                      Repository.last.user_username,
                      Repository.last.slug
                    )
        expect(flash[:notice]).to eq("Success")
      end
    end
  end

  describe "#link_to_pp" do
    context "Link to PP" do
      it "should link to pp" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        pp = create(:project_proposal, :approved)
        repo = create(:repository)
        post :link_to_pp,
             params: {
               repo: {
                 repository_id: repo.id,
                 project_proposal_id: pp.id
               },
               commit: "link",
               user_username: User.last.username
             }
        expect(flash[:notice]).to eq(
          "This Repository was linked to the selected Project Proposal"
        )
        expect(Repository.last.project_proposal_id).to eq(pp.id)
      end
    end
  end

  describe "#add_member" do
    context "Add Member" do
      before(:each) do
        @owner = create(:user, :regular_user)
        @member = create(:user, :regular_user)
        session[:user_id] = @owner.id
        session[:expires_at] = Time.zone.now + 10_000

        @repo =
          create(
            :repository,
            user_id: @owner.id,
            user_username: @owner.username
          )
        Repository.find(@repo.id).users = [@owner]
      end

      it "should not add member twice" do
        post :add_member,
             params: {
               user_username: @owner.username,
               repo_owner: {
                 repository_id: @repo.id,
                 owner_id: @member.id
               }
             }
        post :add_member,
             params: {
               user_username: @owner.username,
               repo_owner: {
                 repository_id: @repo.id,
                 owner_id: @member.id
               }
             }
        expect(flash[:alert]).to eq(
          "This user is already a member of your repository."
        )
        expect(@repo.users.last.id).to eq(@member.id)
      end
    end
  end

  describe "#remove_member" do
    context "Remove Member" do
      before(:each) do
        @owner = create(:user, :regular_user)
        @member = create(:user, :regular_user)
        session[:user_id] = @owner.id
        session[:expires_at] = Time.zone.now + 10_000

        @repo =
          create(
            :repository,
            user_id: @owner.id,
            user_username: @owner.username
          )
        Repository.find(@repo.id).users = [@owner]
      end

      it "should not remove last member from repo" do
        post :remove_member,
             params: {
               user_username: @owner.username,
               repo_owner: {
                 repository_id: @repo.id,
                 owner_id: @owner.id
               }
             }
        expect(flash[:alert]).to eq(
          "You cannot remove the last person in this repository. Please go to your profile page if you want to delete this repository."
        )
        expect(@repo.users.last.id).to eq(@owner.id)
      end

      it "should remove members" do
        post :add_member,
             params: {
               user_username: @owner.username,
               repo_owner: {
                 repository_id: @repo.id,
                 owner_id: @member.id
               }
             }
        expect(@repo.users.last.id).to eq(@member.id)
        post :remove_member,
             params: {
               user_username: @owner.username,
               repo_owner: {
                 repository_id: @repo.id,
                 owner_id: @member.id
               }
             }
        expect(flash[:notice]).to eq(
          "This user was removed from your repository."
        )
        expect(@repo.users.last.id).to eq(@owner.id)
      end

      it "should not remove owner" do
        post :add_member,
             params: {
               user_username: @owner.username,
               repo_owner: {
                 repository_id: @repo.id,
                 owner_id: @member.id
               }
             }
        post :remove_member,
             params: {
               user_username: @owner.username,
               repo_owner: {
                 repository_id: @repo.id,
                 owner_id: @owner.id
               }
             }
        expect(flash[:alert]).to eq(
          "You cannot remove the current owner of this repository."
        )
        expect(@repo.users.first.id).to eq(@owner.id)
      end
    end
  end

  describe "#transfer_owner" do
    context "Transfer Owner" do
      before(:each) do
        @owner = create(:user, :regular_user)
        @member = create(:user, :regular_user)
        session[:user_id] = @owner.id
        session[:expires_at] = Time.zone.now + 10_000

        @repo =
          create(
            :repository,
            user_id: @owner.id,
            user_username: @owner.username
          )
        Repository.find(@repo.id).users = [@owner, @member]
      end

      it "should transfer ownership" do
        post :transfer_owner,
             params: {
               user_username: @owner.username,
               repo_owner: {
                 repository_id: @repo.id,
                 owner_id: @member.id
               }
             }
        expect(flash[:notice]).to eq(
          "Repository ownership was successfully transferred."
        )
        expect(Repository.last.user_id).to eq(@member.id)
      end

      it "should not transfer ownership" do
        post :transfer_owner,
             params: {
               user_username: @owner.username,
               repo_owner: {
                 repository_id: @repo.id,
                 owner_id: @owner.id
               }
             }
        expect(flash[:alert]).to eq(
          "This user is already the owner of the repository."
        )
        expect(Repository.last.user_id).to eq(@owner.id)
      end

      it "should not transfer ownership to a non-member" do
        @non_member = create(:user, :regular_user)
        post :transfer_owner,
             params: {
               user_username: @owner.username,
               repo_owner: {
                 repository_id: @repo.id,
                 owner_id: @non_member.id
               }
             }
        expect(flash[:alert]).to eq(
          "This user is not a member of your repository."
        )
        expect(Repository.last.user_id).to eq(@owner.id)
      end
    end
  end
end
