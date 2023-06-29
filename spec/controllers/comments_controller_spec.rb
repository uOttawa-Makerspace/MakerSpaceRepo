require "rails_helper"

RSpec.describe CommentsController, type: :controller do
  describe "POST /create" do
    before(:all) { @user = create(:user, :regular_user) }

    before(:each) do
      session[:expires_at] = DateTime.tomorrow.end_of_day
      session[:user_id] = @user.id
    end

    context "create comment" do
      it "should create a comment" do
        repo = create(:repository)
        expect {
          post :create, params: { id: repo.id, content: "abc" }
        }.to change(Comment, :count).by(1)
        expect(response).to redirect_to repository_path(
                      id: repo.id,
                      user_username: repo.user_username,
                      anchor: "repo-comments"
                    )
      end

      it "should fail to create a comment" do
        repo = create(:repository)
        expect { post :create, params: { id: repo.id, content: "" } }.to change(
          Comment,
          :count
        ).by(0)
        expect(response).to redirect_to repository_path(
                      id: repo.id,
                      user_username: repo.user_username,
                      anchor: "repo-comments"
                    )
      end
    end
  end

  describe "DELETE /destroy" do
    before(:each) do
      session[:expires_at] = DateTime.tomorrow.end_of_day
      @comment = create(:comment)
    end

    context "logged as the comment's owner" do
      it "should delete their own comment" do
        session[:user_id] = @comment.user.id
        delete :destroy, params: { id: @comment.id }
        expect(flash[:notice]).to eq("Comment deleted succesfully")
      end
    end

    context "logged as not the comment's owner" do
      it "should be not delete other user's comment" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        delete :destroy, params: { id: @comment.id }
        expect(flash[:alert]).to eq("Something went wrong")
      end
    end

    context "logged as admin" do
      it "admins should be able to delete any comment" do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        delete :destroy, params: { id: @comment.id }
        expect(flash[:notice]).to eq("Comment deleted succesfully")
      end
    end
  end

  describe "vote" do
    context "votes" do
      before(:each) do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        repository = create(:repository)
      end

      it "should upvote the comment" do
        comment = create(:comment)
        post :vote,
             params: {
               comment_id: comment.id,
               downvote: "f",
               id: Repository.last.id
             }
        expect(Comment.find(comment.id).user.reputation).to eq(2)
        expect(Comment.find(comment.id).upvote).to eq(1)
      end

      it "should downvote the comment" do
        comment = create(:comment)
        post :vote,
             params: {
               comment_id: comment.id,
               downvote: "t",
               id: Repository.last.id
             }
        expect(Comment.find(comment.id).user.reputation).to eq(-2)
        expect(Comment.find(comment.id).upvote).to eq(-1)
      end
    end

    context "voted" do
      before(:each) { repository = create(:repository) }

      it "should downvote an upvoted comment" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        comment = create(:comment)
        Upvote.create(user_id: user.id, comment_id: comment.id, downvote: false)
        post :vote,
             params: {
               comment_id: comment.id,
               downvote: "t",
               id: Repository.last.id
             }
        expect(Comment.find(comment.id).upvote).to eq(-1)
      end

      it "should remove an existing downvote" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10_000
        comment = create(:comment)
        Upvote.create(user_id: user.id, comment_id: comment.id, downvote: true)
        post :vote,
             params: {
               comment_id: comment.id,
               downvote: "t",
               id: Repository.last.id
             }
        expect(Comment.find(comment.id).upvote).to eq(0)
      end
    end
  end
end
