require 'rails_helper'

RSpec.describe LabSession, type: :model do

  describe 'Association' do

    context 'belongs_to' do
      it { should belong_to(:user) }
      it { should belong_to(:space) }
    end

  end

  describe "Scopes" do

    context "#between_dates_picked" do

      it 'should get the dates' do
        create(:lab_session, created_at: DateTime.yesterday.end_of_day, updated_at: DateTime.yesterday.end_of_day)
        create(:lab_session, created_at: DateTime.now.end_of_day, updated_at: DateTime.now.end_of_day)
        create(:lab_session, created_at: DateTime.tomorrow.end_of_day, updated_at: DateTime.tomorrow.end_of_day)
        expect(LabSession.between_dates_picked(DateTime.yesterday.beginning_of_day, DateTime.now.end_of_day).count).to eq(2)
        expect(LabSession.between_dates_picked(3.days.ago.beginning_of_day, 2.days.ago.beginning_of_day).count).to eq(0)
        expect(LabSession.between_dates_picked(3.days.ago.beginning_of_day, 3.days.from_now).count).to eq(3)
      end

    end

  end

end
