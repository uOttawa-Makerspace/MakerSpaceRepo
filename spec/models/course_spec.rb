require 'rails_helper'

RSpec.describe Course, type: :model do

  # describe 'Association' do
  #   context 'has_many' do
  #     it { should have_many(:training_sessions) }
  #   end
  # end

  describe 'Validations' do
    context 'presence and uniqueness' do
      it { should validate_presence_of(:name) }
      it { should validate_uniqueness_of(:name) }
    end
  end

end
