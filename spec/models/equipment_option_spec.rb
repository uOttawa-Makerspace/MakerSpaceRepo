require 'rails_helper'

RSpec.describe EquipmentOption, type: :model do
  describe 'Validations' do
    context 'presence' do
      it { should validate_presence_of(:name) }
    end
  end

  describe 'Scopes' do
    context 'show_options' do
      it 'should order all equipment options' do
        first_equipment_option = create(:equipment_option, name: "a as first letter")
        last_equipment_option = create(:equipment_option, name: "z as first letter")
        middle_equipment_option = create(:equipment_option, name: "f as first letter")
        expect(EquipmentOption.show_options.count).to eq(3)
        expect(EquipmentOption.show_options.pluck(:name)).to eq([first_equipment_option.name, middle_equipment_option.name, last_equipment_option.name])
      end
    end
  end
end
