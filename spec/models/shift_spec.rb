require 'rails_helper'

RSpec.describe Shift, type: :model do
  describe 'Association' do
    context 'belongs_to' do
      it { should belong_to(:space) }
    end

    context 'has_and_belongs_to_many' do
      it { should have_and_belong_to_many(:users) }
    end
  end

  describe 'Validations' do

    context 'start_datetime' do
      it { should validate_presence_of(:start_datetime) }
    end

    context 'end_datetime' do
      it { should validate_presence_of(:end_datetime) }
    end
  end
end
