require "rails_helper"

RSpec.describe FaqsController, type: :controller do
  before(:each) { session[:user_id] = (create :user, :admin).id }

  describe "GET /index" do
    context "logged in as admin" do
      it "should return http success" do
        get :index
        expect(response).to have_http_status(:success)
      end
    end

    context "not logged in" do
      it "should return http success" do
        session[:user_id] = nil
        get :index
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "POST /" do
    context "not logged in" do
      it "should redirect" do
        session[:user_id] = nil
        faq = create :faq
        expect {
          post :create, params: { faq: (attributes_for :faq) }
        }.to change(Faq, :count).by(0)
        expect(response).to redirect_to root_path
      end
    end

    context "logged in" do
      it "should create FAQ entry" do
        faq = create :faq
        expect {
          post :create, params: { faq: (attributes_for :faq) }
        }.to change(Faq, :count).by(1)
        # Add entries quickly
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "Edit FAQ Entries" do
    context "PATCH entry" do
      it "should update entry" do
        faq = create :faq
        new_title_en = "new title"
        new_body_fr = "nouvelle texte"
        patch :update,
              params: {
                id: faq.id,
                faq: {
                  title_en: "new title",
                  body_fr: "nouvelle texte"
                }
              }
        faq.reload
        expect(faq.title_en).to eq(new_title_en)
        expect(faq.body_fr).to eq(new_body_fr)
      end
    end
    context "reorder entries" do
      it "should reorder entries, create values for others" do
        faq_list = create_list :faq, 5 # make 5 entries
        # Reorder and take last three
        reorder_list = faq_list.shuffle.take 3
        put :reorder, params: { data: reorder_list, format: "json" }
        faq_list.each { |f| f.reload }
        # first three are ordered
        reorder_list[0].order = 0
        reorder_list[1].order = 1
        reorder_list[2].order = 2
        faq_list[3].order.present?
        faq_list[4].order.present?
      end
    end
  end
end
