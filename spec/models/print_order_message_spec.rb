require 'rails_helper'

RSpec.describe PrintOrderMessage, type: :model do
  describe 'Validations' do
    context 'presence' do
      it { should validate_presence_of(:name) }
      it { should validate_uniqueness_of(:name) }
      it { should validate_presence_of(:message) }
    end
  end
end
