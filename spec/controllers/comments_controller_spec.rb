require 'rails_helper'

RSpec.describe CommentsController, type: :controller do

  describe 'delete method' do

    before(:each) do
      create :user, :regular_user
      create(:repository, :repository)
      session[:expires_at] = 'Sat, 03 Jun 2030 05:01:41 UTC +00:00'
    end

    context 'users can delete their own comments' do

      it 'should be deleting the user\'s comment' do
        comment1 = create(:comment, :comment)
        session[:user_id] = comment1.user_id
        delete :destroy, params: {id: comment1.id}
        expect(flash[:notice]).to eq('Comment deleted succesfully')
      end

    end

    context 'admins can delete any comment' do

      it 'should be deleting the user\'s comment' do
        comment1 = create(:comment, :comment)
        session[:user_id] = (create :user, :admin_user).id
        delete :destroy, params: {id: comment1.id}
        expect(flash[:notice]).to eq('Comment deleted succesfully')
      end

    end

    context 'users can\'t delete others\' comments' do

      it 'should be not deleting the user\'s comment' do
        comment1 = create(:comment, :comment)
        session[:user_id] = (create :user, :other_user).id
        delete :destroy, params: {id: comment1.id}
        expect(flash[:alert]).to eq('Something went wrong')
      end

    end

  end

end