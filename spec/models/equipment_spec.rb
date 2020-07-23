require 'rails_helper'

RSpec.describe Equipment, type: :model do
  describe 'Association' do
    context 'belongs_to' do
      it { should belong_to(:repository) }
    end
  end
end
