require 'rails_helper'

RSpec.describe CommentsController, type: :controller do

  describe 'delete method' do

    context 'users can delete their own comments' do

      it 'should be deleting the user\'s comment' do
        user1 = create(:user)
        repo1 = create(:repository)
        comment1 = create(:comment)
        puts(comment1.repository.user_username)
        session[:user_id] = comment1.user_id
        session[:expires_at] = 'Sat, 03 Jun 2030 05:01:41 UTC +00:00'
        delete :destroy, params: {id: comment1.id}
        expect(flash[:notice]).to eq('Comment deleted succesfully')
      end

    end

  end

end