require 'rails_helper'

RSpec.describe OrderStatus, type: :model do
  describe 'Association' do

    context 'has_many' do
      it { should have_many(:orders) }
    end

  end
end
