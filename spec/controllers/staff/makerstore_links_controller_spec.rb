require "rails_helper"

RSpec.describe Staff::MakerstoreLinksController, type: :controller do
  before(:each) do
    session[:user_id] = (create :user, :staff).id
    session[:expires_at] = Time.zone.now + 10_000
  end

  describe "GET /index" do
    context "logged in as staff" do
      it "should return http success" do
        get :index
        expect(response).to have_http_status(:success)
      end
    end

    context "not logged in" do
      it "should return http redirect" do
        session[:user_id] = nil
        get :index
        expect(response).to_not have_http_status(:success)
      end
    end
  end

  describe "POST /create" do
    context "create a new link" do
      it "should create link" do
        makerstore_link_params =
          FactoryBot.attributes_for(:makerstore_link, :with_image)
        expect {
          post :create, params: { makerstore_link: makerstore_link_params }
        }.to change(MakerstoreLink, :count).by 1
      end

      it "should reject link without image" do
        makerstore_link_params = FactoryBot.attributes_for(:makerstore_link)
        expect {
          post :create, params: { makerstore_link: makerstore_link_params }
        }.to change(MakerstoreLink, :count).by 0
        expect(flash[:alert]&.empty?).to be_falsy
      end
    end
  end

  describe "PATCH #update" do
    context "hiding and showing a link" do
      it "should hide a link" do
        link = create(:makerstore_link, :with_image)
        put :update, params: { id: link.id, makerstore_link: { shown: false } }
        expect(MakerstoreLink.find(link.id).shown).to be false
      end

      it "should show a link" do
        link = create(:makerstore_link, :with_image, :hidden)
        put :update, params: { id: link.id, makerstore_link: { shown: true } }
        expect(MakerstoreLink.find(link.id).shown).to be true
      end
    end
  end
end
