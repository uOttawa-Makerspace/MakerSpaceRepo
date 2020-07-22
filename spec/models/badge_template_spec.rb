require 'rails_helper'

RSpec.describe BadgeTemplate, type: :model do

  describe "Associations" do

    context "has_many" do
      it { should have_many(:badge_requirements) }
      it { should have_many(:badges) }
      it { should have_many(:proficient_projects) }
    end

  end

  describe "methods" do

    context "#acclaim_api_get_all_badge_templates" do

      it 'should show the badge templates' do
        expect(BadgeTemplate.acclaim_api_get_all_badge_templates['data'][0]['id']).to_not be_nil
      end

    end

  end

end
