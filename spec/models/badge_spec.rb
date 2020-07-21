require 'rails_helper'

RSpec.describe Badge, type: :model do

  describe "Associations" do

    context "belongs_to" do
      it { should belong_to(:user) }
      it { should belong_to(:badge_template) }
    end

  end

  describe "methods" do

    context "#filter_by_attribute" do

      before(:each) do
        create(:badge_template, :'3d_printing')
        create(:badge, :'3d_printing')
        create(:badge_template, :laser_cutting)
        create(:badge, :laser_cutting)
        create(:badge_template, :arduino)
        create(:badge, :arduino)
      end

      it 'should get all the badges' do
        expect(Badge.joins(:badge_template).all.filter_by_attribute("search=").count).to eq(Badge.all.count)
      end

      it 'should get the searched badges' do
        expect(Badge.joins(:badge_template).all.filter_by_attribute("search=3d").count).to eq(1)
      end

      it 'should get the searched badges' do
        expect(Badge.joins(:badge_template).all.filter_by_attribute("search=2D modelling").count).to eq(1)
      end

    end

  end

end
