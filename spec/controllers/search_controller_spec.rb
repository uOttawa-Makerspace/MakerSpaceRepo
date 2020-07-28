require 'rails_helper'

RSpec.describe SearchController, type: :controller do

  describe "GET /explore" do

    context "explore" do

      before(:all) do
        (0..15).each do
          create(:repository)
        end
      end

      it 'should get a 200' do
        get :explore
        expect(response).to have_http_status(:success)
      end

      it 'should get a 200 on the second page' do
        get :explore, params: {page: 2}
        expect(response).to have_http_status(:success)
      end

      it 'should sort by newest' do
        get :explore, params: {sort: "newest"}
        expect(response).to have_http_status(:success)
      end

      it 'should sort by most likes' do
        get :explore, params: {sort: "most_likes"}
        expect(response).to have_http_status(:success)
      end

      it 'should sort by most makes' do
        get :explore, params: {sort: "most_makes"}
        expect(response).to have_http_status(:success)
      end

      it 'should sort by recently_updated' do
        get :explore, params: {sort: "recently_updated"}
        expect(response).to have_http_status(:success)
      end

    end

  end

  describe "GET /search" do

    context "search" do

      it 'should search for the right result' do
        create(:repository)
        create(:repository, description: "Donec malesuada lacus lorem, ac finibus nibh ultrices quis. Duis dignissim nisl tristique convallis dignissim.")
        get :search, params: {q: "Donec malesuada lacus lorem, ac finibus nibh ultrices quis."}
        expect(@controller.instance_variable_get(:@repositories).count).to eq(1)
        expect(response).to have_http_status(:success)
      end

      it 'should get no results' do
        create(:repository)
        create(:repository)
        create(:repository)
        get :search, params: {q: "Donec malesuada lacus lorem, ac finibus nibh ultrices quis."}
        expect(@controller.instance_variable_get(:@repositories).count).to eq(0)
        expect(response).to have_http_status(:success)
      end

    end

  end

  describe "GET /search" do

    context "search" do

      it 'should search for the right result' do
        create(:repository)
        create(:repository, description: "Donec malesuada lacus lorem, ac finibus nibh ultrices quis. Duis dignissim nisl tristique convallis dignissim.")
        get :search, params: {q: "Donec malesuada lacus lorem, ac finibus nibh ultrices quis."}
        expect(@controller.instance_variable_get(:@repositories).count).to eq(1)
        expect(response).to have_http_status(:success)
      end

      it 'should get no results' do
        create(:repository)
        create(:repository)
        create(:repository)
        get :search, params: {q: "Donec malesuada lacus lorem, ac finibus nibh ultrices quis."}
        expect(@controller.instance_variable_get(:@repositories).count).to eq(0)
        expect(response).to have_http_status(:success)
      end

    end

  end

  describe "GET /category" do

    context "category" do

      before(:each) do
        CategoryOption.create(name: "Internet of Things")
        create(:repository)
        create(:repository)
      end

      it 'should get all the repo with the right category' do
        repo = create(:repository)
        Category.create(repository_id: repo.id, name: "Internet of Things")
        get :category, params: {slug: "internet-of-things"}
        expect(@controller.instance_variable_get(:@repositories).count).to eq(1)
        expect(response).to have_http_status(:success)
      end

      it 'should get no results' do
        get :category, params: {slug: "internet-of-things"}
        expect(@controller.instance_variable_get(:@repositories).count).to eq(0)
        expect(response).to have_http_status(:success)
      end

      it 'should get the featured results' do
        repo = create(:repository, featured: true)
        Category.create(repository_id: repo.id, name: "Internet of Things")
        get :category, params: {slug: "internet-of-things", featured: "yes"}
        expect(@controller.instance_variable_get(:@repositories).count).to eq(1)
        expect(response).to have_http_status(:success)
      end

    end

  end

  describe "GET /equipment" do

    context "equipment" do

      before(:each) do
        EquipmentOption.create(name: "3D Printer")
        create(:repository)
        create(:repository)
      end

      it 'should get all the repo with the right category' do
        repo = create(:repository)
        Equipment.create(repository_id: repo.id, name: "3D Printer")
        get :equipment, params: {slug: "3D Printer"}
        expect(@controller.instance_variable_get(:@repositories).count).to eq(1)
        expect(response).to have_http_status(:success)
      end

      it 'should get no results' do
        get :equipment, params: {slug: "internet-of-things"}
        expect(@controller.instance_variable_get(:@repositories).count).to eq(0)
        expect(response).to have_http_status(:success)
      end

    end

  end

end

