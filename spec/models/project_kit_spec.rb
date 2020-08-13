require 'rails_helper'

RSpec.describe ProjectKit, type: :model do
  describe 'Association' do
    context 'belongs_to' do
      it { should belong_to(:proficient_project) }
      it { should belong_to(:user) }
    end
  end
end
