require 'rails_helper'

RSpec.describe UsersController, type: :controller do

  describe "new" do

    context 'new' do

      it 'should redirect the already signed_in user to the root' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :new
        expect(response).to redirect_to root_path
      end

      it 'should give a 200' do
        get :new
        expect(response).to have_http_status(:success)
      end

    end

  end

  describe 'create' do

    context 'create user' do

      it 'should create the user' do
        user_params = FactoryBot.attributes_for(:user, :regular_user, password: "asa32A353#")
        expect { post :create, params: {user: user_params} }.to change(User, :count).by(1)
        expect(response).to redirect_to settings_profile_path("Bob")
        expect(flash[:notice]).to eq('Profile created successfully.')
      end

      it 'should create the user with avatar' do
        user_params = FactoryBot.attributes_for(:user, :regular_user_with_avatar, password: "asa32A353#")
        expect { post :create, params: {user: user_params} }.to change(User, :count).by(1)
        expect(response).to redirect_to settings_profile_path("Bob")
        expect(flash[:notice]).to eq('Profile created successfully.')
      end

      it 'should create the user with avatar' do
        user_params = FactoryBot.attributes_for(:user, :regular_user, username: "abcdefghijklmnopqrstuvwxyz")
        expect { post :create, params: {user: user_params} }.to change(User, :count).by(0)
        expect(response).to have_http_status(422)
      end

    end

  end

  describe 'remove_avatar' do

    context 'remove avatar' do

      it 'should remove the avatar and display the default avatar' do
        user = create(:user, :regular_user_with_avatar)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :remove_avatar
        expect(response).to redirect_to settings_profile_path
        expect(User.display_avatar(User.find(user.id))).to eq('default-avatar.png')
      end

      it 'should remove nothing and not give an error' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :remove_avatar
        expect(response).to redirect_to settings_profile_path
        expect(User.display_avatar(User.find(user.id))).to eq('default-avatar.png')
      end
    end

  end

  describe 'update' do

    context 'update' do

      it 'should update the profile' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        patch :update, params: {username: "Bob", user: {name: "John Doe"}}
        expect(response).to redirect_to settings_profile_path
        expect(flash[:notice]).to eq('Profile updated successfully.')
      end

      it 'should fail to update the profile' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        patch :update, params: {username: "Bob", user: {name: ""}}
        expect(response).to redirect_to settings_profile_path
        expect(flash[:alert]).to eq('Could not save changes.')
      end

    end

  end

  describe 'change_password' do

    context 'change user\'s password' do

      it 'should change the password' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        @oldpass = user.password
        patch :change_password, params: {username: user.username, user: {old_password: 'asa32A353#', password: 'Password2', password_confirmation: 'Password2'}}
        @newpass = User.find(user.id).password
        expect(@oldpass).not_to be(@newpass)
        expect(response).to redirect_to settings_admin_path
        expect(flash[:notice]).to eq('Password changed successfully')
      end

      it 'shouldn\'t change password (Wrong password)' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        patch :change_password, params: {username: user.username, user: {old_password: 'Password1', password: 'Password2', password_confirmation: 'Password2'}}
        expect(response).to have_http_status(:success)
        expect(flash[:alert]).to eq('Incorrect old password.')
      end

      it 'shouldn\'t change password (Confirmation doesn\'t match)' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        @oldpass = user.password
        patch :change_password, params: {username: user.username, user: {old_password: 'asa32A353#', password: 'Password2', password_confirmation: 'Password3'}}
        @newpass = User.find(user.id).password
        expect(@oldpass).not_to be(@newpass)
        expect(response).to have_http_status(:success)
      end

    end
  end

  describe "show" do

    context 'repo user' do

        it 'should return the right repo user (own page)' do
          user = create(:user, :regular_user)
          session[:user_id] = user.id
          session[:expires_at] = Time.zone.now + 10000
          get :show, params: {username: user.username}
          expect(@controller.instance_variable_get(:@repo_user).id).to eq(user.id)
        end

        it 'should return the right repo user (someone elses)' do
          user = create(:user, :regular_user)
          other_user = create(:user, :other_user)
          session[:user_id] = user.id
          session[:expires_at] = Time.zone.now + 10000
          get :show, params: {username: other_user.username}
          expect(@controller.instance_variable_get(:@repo_user).id).to eq(other_user.id)
        end

      end

      describe 'repos' do

        it 'should get all repos' do
          user = create(:user, :regular_user)
          session[:user_id] = user.id
          session[:expires_at] = Time.zone.now + 10000
          create(:repository, :repository)
          Repository.last.users << User.find(user.id)
          create(:repository, :private)
          Repository.last.users << User.find(user.id)
          get :show, params: {username: user.username}
          expect(@controller.instance_variable_get(:@repositories).count).to eq(2)
        end

        it 'should get only public repos' do
          user = create(:user, :other_user)
          other_user = create(:user, :regular_user)
          session[:user_id] = user.id
          session[:expires_at] = Time.zone.now + 10000
          create(:repository, :repository)
          Repository.last.users << User.find(other_user.id)
          create(:repository, :private)
          Repository.last.users << User.find(other_user.id)
          get :show, params: {username: other_user.username}
          expect(@controller.instance_variable_get(:@repositories).count).to eq(1)
        end

      end

      describe "badge url" do

        it 'should return the share link' do
          user = create(:user, :regular_user)
          session[:user_id] = user.id
          session[:expires_at] = Time.zone.now + 10000
          get :show, params: {username: user.username}
          expect(@controller.instance_variable_get(:@acclaim_badge_url)).to eq('https://www.youracclaim.com/earner/earned/share/')
        end

        it 'should return the public link' do
          user = create(:user, :regular_user)
          other_user = create(:user, :other_user)
          session[:user_id] = user.id
          session[:expires_at] = Time.zone.now + 10000
          get :show, params: {username: other_user.username}
          expect(@controller.instance_variable_get(:@acclaim_badge_url)).to eq('https://www.youracclaim.com/badges/')
        end

      end

    end

    describe 'likes' do
      context 'likes' do

        it 'should display 2 likes' do
          user = create(:user, :regular_user)
          session[:user_id] = user.id
          session[:expires_at] = Time.zone.now + 10000
          create(:repository, :repository)
          create(:repository, :private)
          create(:like, :repo1)
          create(:like, :repo2)
          get :likes, params: {username: user.username}
          expect(response).to have_http_status(:success)
          expect(@controller.instance_variable_get(:@repositories).count).to eq(2)
        end

      end
    end

    describe 'destroy' do
      context 'destroy' do

        it 'should delete the user' do
          user = create(:user, :regular_user)
          session[:user_id] = user.id
          session[:expires_at] = Time.zone.now + 10000
          delete :destroy, params: {username: user.username}
          expect(response).to redirect_to root_path
          expect { User.find(user.id) }.to raise_exception(ActiveRecord::RecordNotFound)
        end

      end
    end

    describe "vote" do

      context 'votes' do

        it 'should up vote the comment' do
          user = create(:user, :regular_user)
          session[:user_id] = user.id
          session[:expires_at] = Time.zone.now + 10000
          create(:repository, :repository)
          comment = create(:comment, :comment)
          create(:comment, :other_comment)
          post :vote, params: {comment_id: comment.id, downvote: "f", voted: false}, format: 'json'
          expect(User.find(user.id).reputation).to eq(2)
          expect(Comment.find(comment.id).upvote).to eq(1)
        end

        it 'should up down vote the comment' do
          user = create(:user, :regular_user)
          session[:user_id] = user.id
          session[:expires_at] = Time.zone.now + 10000
          create(:repository, :repository)
          comment = create(:comment, :comment)
          create(:comment, :other_comment)
          post :vote, params: {comment_id: comment.id, downvote: "t", voted: false}, format: 'json'
          expect(User.find(user.id).reputation).to eq(-2)
          expect(Comment.find(comment.id).upvote).to eq(-1)
        end

      end

      context 'voted' do

        it 'should up downvote an upvoted comment the comment' do
          user = create(:user, :regular_user)
          session[:user_id] = user.id
          session[:expires_at] = Time.zone.now + 10000
          create(:repository, :repository)
          comment = create(:comment, :comment, upvote: 1)
          Upvote.create(user_id: user.id, comment_id: comment.id, downvote: false)
          create(:comment, :other_comment)
          post :vote, params: {comment_id: comment.id, downvote: "t", voted: true}, format: 'json'
          expect(Comment.find(comment.id).upvote).to eq(0)
        end

        it 'should up downvote an downvoted comment the comment' do
          user = create(:user, :regular_user)
          session[:user_id] = user.id
          session[:expires_at] = Time.zone.now + 10000
          create(:repository, :repository)
          comment = create(:comment, :comment, upvote: -1)
          Upvote.create(user_id: user.id, comment_id: comment.id, downvote: true)
          create(:comment, :other_comment)
          post :vote, params: {comment_id: comment.id, downvote: "t", voted: true}, format: 'json'
          expect(Comment.find(comment.id).upvote).to eq(-1)
        end

        it 'should up downvote an downvoted comment the comment' do
          user = create(:user, :regular_user)
          session[:user_id] = user.id
          session[:expires_at] = Time.zone.now + 10000
          create(:repository, :repository)
          comment = create(:comment, :comment)
          create(:comment, :other_comment)
          post :vote, params: {comment_id: comment.id, downvote: "t", voted: true}, format: 'json'
          expect(response).to have_http_status(500)
        end

      end

    end

  end


