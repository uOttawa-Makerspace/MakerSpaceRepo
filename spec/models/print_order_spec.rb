require 'rails_helper'

RSpec.describe PrintOrder, type: :model do

  before(:all) do
    build :user, :regular_user
  end

  context 'validate file type' do
    it 'should be false' do
      print_order = build(:print_order, :with_invalid_file)
      expect(print_order.valid?).to be_falsey
    end

    it 'should be true' do
      print_order = build :print_order
      expect(print_order.valid?).to be_truthy
    end
  end

end
