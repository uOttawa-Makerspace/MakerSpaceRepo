require 'rails_helper'

RSpec.describe HelpController, type: :controller do
  before do
    # Stub the github issue service to return a random value instead of calling the API
    allow(GithubIssuesService).to receive_message_chain(
      :new,
      :create_issue
    ).and_return(OpenStruct.new({ number: Faker::Number.number(digits: 5) }))
  end

  context 'Sending a help request' do
    describe 'Fetching page' do
      it 'should allow non-logged in users' do
        get :show
        expect(response).to have_http_status(:success)
      end
    end

    describe 'Sending a help request' do
      it 'should accept a valid help form' do
        expect {
          post :create,
               params: {
                 help: {
                   name: 'John',
                   email: 'john@doe.com',
                   subject: 'HELPHELPHELPHELP',
                   comments: 'HELP !!!'
                 }
               }
        }.to have_enqueued_mail(MsrMailer, :issue_email)
        expect(flash[:notice]).not_to be nil
        expect(response).to redirect_to help_path
      end
    end
  end
end
