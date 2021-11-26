require 'rails_helper'

RSpec.describe Shift, type: :model do
  describe 'Association' do
    context 'belongs_to' do
      it { should belong_to(:user) }
      it { should belong_to(:space) }
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
