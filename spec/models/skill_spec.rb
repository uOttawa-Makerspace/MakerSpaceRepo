require 'rails_helper'

RSpec.describe Skill, type: :model do

  describe 'Association' do

    context 'belongs_to' do
      it { should belong_to(:user) }
    end

  end

  describe "Validations" do

    context "user_id" do

      it { should validate_uniqueness_of(:user_id)}

    end

  end

end
