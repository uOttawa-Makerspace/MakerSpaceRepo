require 'rails_helper'

RSpec.describe AreaOption, type: :model do
  describe 'Validations' do
    context 'presence' do
      it { should validate_presence_of(:name) }
    end
  end

  describe 'Scopes' do
    context 'show_options' do
      it 'should order all area options' do
        first_area_option = create(:area_option, name: "a as first letter")
        last_area_option = create(:area_option, name: "z as first letter")
        middle_area_option = create(:area_option, name: "f as first letter")
        expect(AreaOption.show_options.count).to eq(3)
        expect(AreaOption.show_options.pluck(:name)).to eq([first_area_option.name, middle_area_option.name, last_area_option.name])
      end
    end
  end
end
