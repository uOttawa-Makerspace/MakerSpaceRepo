require 'rails_helper'

RSpec.describe HelpController, type: :controller do
  context 'GET /main' do
    describe 'without being logged in' do
      it 'should give a 200' do
        get :main
        expect(response).to have_http_status(:success)
      end
    end
  end

  context 'PUT /send_email' do
    describe "submit help" do
      it 'should send an email' do
        put :send_email, params: {name: "John", email: "john@doe.com", subject: "HELP", message: "HELP !!!"}
        expect(ActionMailer::Base.deliveries.count).to eq(1)
        expect(ActionMailer::Base.deliveries.first.to.first).to eq("john@doe.com")
        expect(flash[:notice]).to eq("Email successfuly send. You will be contacted soon.")
        expect(response).to redirect_to help_path
      end
    end
  end
end


