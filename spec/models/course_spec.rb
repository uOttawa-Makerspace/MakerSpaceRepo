require 'rails_helper'

RSpec.describe Course, type: :model do
  describe 'Association' do
    context 'has_many' do
      it { should have_many(:training_sessions) }
    end
  end
end
