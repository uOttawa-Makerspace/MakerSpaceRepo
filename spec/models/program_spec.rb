require 'rails_helper'

RSpec.describe Program, type: :model do
  describe 'Association' do
    context 'belongs_to' do
      it { should belong_to(:user) }
    end
  end

  describe 'Validations' do
    context "user" do
      it { should validate_presence_of(:user).with_message('A user is required.') }
      it { should validate_uniqueness_of(:user).scoped_to(:program_type).with_message('An user can only join a program once') }
      it { should validate_presence_of(:program_type).with_message("The type of the program is required. Either 'Volunteer Program' or 'Development Program'") }
    end
  end
end
