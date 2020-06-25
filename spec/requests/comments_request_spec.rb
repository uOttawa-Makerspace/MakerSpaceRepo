require 'rails_helper'

RSpec.describe "Comments", type: :request do

  describe "validations" do

    context "users can delete their own comments" do
      it "should be have flash message successful" do
        delete :destroy, id: create(:comment).id
        expect(flash[:notice]).to eq('Comment deleted succesfully')
      end
    end

  end

end
