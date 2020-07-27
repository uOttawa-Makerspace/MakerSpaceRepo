require 'rails_helper'

RSpec.describe Certification, type: :model do
  describe 'Association' do
    context 'belongs_to' do
      it { should belong_to(:user) }
      it { should belong_to(:training_session) }
    end

    context 'has_one' do
      it { should have_one(:space) }
      it { should have_one(:training) }
    end
  end

  describe 'Validations' do
    context 'presence' do
      it { should validate_presence_of(:user).with_message('A user is required.') }
      it { should validate_presence_of(:training_session).with_message('A training session is required.') }
    end
  end

  describe 'Scopes' do
    context '#between_dates_picked' do
      it 'should return certifications between dates' do
        create(:certification, created_at: DateTime.yesterday.end_of_day, updated_at: DateTime.yesterday.end_of_day)
        create(:certification, created_at: DateTime.now.end_of_day, updated_at: DateTime.now.end_of_day)
        create(:certification, created_at: DateTime.tomorrow.end_of_day, updated_at: DateTime.tomorrow.end_of_day)
        expect(Certification.between_dates_picked(DateTime.yesterday.beginning_of_day, DateTime.now.end_of_day).count).to eq(2)
        expect(Certification.between_dates_picked(3.days.ago.beginning_of_day, 2.days.ago.beginning_of_day).count).to eq(0)
        expect(Certification.between_dates_picked(3.days.ago.beginning_of_day, 3.days.from_now).count).to eq(3)
      end
    end
  end

  describe 'Methods' do
    context '#trainer' do
      it "should return the name of the trainer" do
        certification = create(:certification)
        training_session = certification.training_session
        user = training_session.user
        expect(certification.trainer).to eq(User.find(user.id).name)
      end
    end

    context '#out_of_date?' do
      it 'should return false for not expired certification' do
        certification = create(:certification)
        expect(certification.out_of_date?).to eq(false)
      end

      it 'should return true for expired certification' do
        certification = create(:certification, created_at: 3.years.ago, updated_at: 3.years.ago)
        expect(certification.out_of_date?).to eq(true)
      end
    end

    context '#unique_cert' do
      it "should return true if certification is unique" do
        certification = create(:certification)
        expect(certification.unique_cert).to eq(true)
      end

      it "should return false if certification is not unique" do
        certification = create(:certification)
        user = certification.user
        training_session = certification.training_session
        new_certification = user.certifications.new(training_session: training_session)
        expect(new_certification.unique_cert).to eq(false)
      end
    end

    context '#certify_user' do
      it 'should certify user' do
        user = create(:user, :regular_user)
        training_session = create(:training_session)
        expect{ Certification.certify_user(training_session.id, user.id) }.to change{ Certification.count }.by(1)
        expect(Certification.find_by(user: user, training_session: training_session).present?).to eq(true)
      end
    end

    context '#get_badge_path' do
      it 'should return bronze path for beginners' do
        training_session = create(:training_session, level: "Beginner")
        certification = create(:certification, training_session: training_session)
        expect(certification.get_badge_path).to eq('badges/bronze.png')
      end

      it 'should return silver path for Intermediate' do
        training_session = create(:training_session, level: 'Intermediate')
        certification = create(:certification, training_session: training_session)
        expect(certification.get_badge_path).to eq('badges/silver.png')
      end

      it 'should return gold path for Advanced' do
        training_session = create(:training_session, level: 'Advanced')
        certification = create(:certification, training_session: training_session)
        expect(certification.get_badge_path).to eq('badges/golden.png')
      end
    end
  end
end