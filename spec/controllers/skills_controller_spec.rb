require 'rails_helper'
include FilesTestHelper

RSpec.describe SkillsController, type: :controller do

  before(:all) do
    @user = create(:user, :regular_user)
  end

  before(:each) do
    session[:expires_at] = DateTime.tomorrow.end_of_day
    session[:user_id] = @user.id
  end

  describe "GET #edit" do

    context "edit page" do

      it "should get a 200" do

        Skill.create(user_id: @user.id)
        get :edit, params: {id: Skill.find_by_user_id(@user.id).id}
        expect(response).to have_http_status(:success)

      end

    end

  end

  describe "PATCH #update" do

    context "update" do

      it "should redirect to edit_skill_path and update" do
        Skill.create(user_id: @user.id)
        patch :update, params: {id: Skill.find_by_user_id(@user.id).id, skill: {printing: "Beginner"}}
        expect(Skill.find_by_user_id(@user.id).printing).to eq("Beginner")
        expect(response).to redirect_to edit_skill_path
        expect(flash["notice"]).to eq('Skills updated')
      end

    end

  end

end

