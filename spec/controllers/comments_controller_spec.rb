require 'rails_helper'

RSpec.describe CommentsController, type: :controller do
  describe 'delete method' do
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