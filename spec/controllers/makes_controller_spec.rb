require 'rails_helper'

RSpec.describe MakesController, type: :controller do

  before(:each) do
    @user = create(:user, :regular_user)
    session[:expires_at] = DateTime.tomorrow.end_of_day
    session[:user_id] = @user.id
  end

  describe "POST /create" do

    context "create a make" do

      it 'should create a make' do
        repo = create(:repository, :create_equipement_and_categories)
        Repository.last.users << User.last
        Repository.last.save
        expect { post :create, params: {slug: Repository.find(repo.id).slug, user_username: Repository.last.user_username, "#{Repository.find(repo.id).title}": {title: Faker::Lorem.word, description: Faker::Lorem.paragraph}, images: [fixture_file_upload(Rails.root.join('spec/support/assets', 'avatar.png'), 'image/png')]} }.to change(Repository, :count).by(1)
        expect(Repository.last.photos.last.image).to be_attached
        expect(Repository.last.categories.count).to eq(2)
        expect(Repository.last.equipments.count).to eq(2)
      end

    end

  end

  describe "GET /new" do

    context "show the new make page" do

      it 'should get a 200' do
        repo = create(:repository)
        get :new, params: {user_username: Repository.find(repo.id).user_username, slug: Repository.find(repo.id).slug}
        expect(response).to have_http_status(:success)
      end

    end

  end

end

