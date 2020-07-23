require 'rails_helper'

RSpec.describe CommentsController, type: :controller do

  describe 'POST /create' do

    before(:all) do
      @user = create(:user, :regular_user)
    end

    before(:each) do
      session[:expires_at] = DateTime.tomorrow.end_of_day
      session[:user_id] = @user.id
    end

    context "create comment" do

      it "should create a comment" do
        repo = create(:repository)
        expect{ post :create, params: {slug: repo.slug, content: "abc"} }.to change(Comment, :count).by(1)
        expect(response).to redirect_to repository_path(slug: repo.slug, user_username: repo.user_username, :anchor => "repo-comments")
      end

      it "should fail to create a comment" do
        repo = create(:repository)
        expect{ post :create, params: {slug: repo.slug, content: ""} }.to change(Comment, :count).by(0)
        expect(response).to redirect_to root_path
      end

    end

  end

  describe 'DELETE /destroy' do

    before(:each) do
      session[:expires_at] = DateTime.tomorrow.end_of_day
      @comment = create(:comment)
    end

    context "logged as the comment's owner" do
      it "should delete their own comment" do
        session[:user_id] = @comment.user.id
        delete :destroy, params: {id: @comment.id}
        expect(flash[:notice]).to eq('Comment deleted succesfully')
      end
    end

    context "logged as not the comment's owner" do
      it "should be not delete other user's comment" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        delete :destroy, params: {id: @comment.id}
        expect(flash[:alert]).to eq('Something went wrong')
      end
    end

    context 'logged as admin' do
      it 'admins should be able to delete any comment' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        delete :destroy, params: {id: @comment.id}
        expect(flash[:notice]).to eq('Comment deleted succesfully')
      end
    end

  end

end