require 'rails_helper'

RSpec.describe ShadowingHour, type: :model do
  it { should belong_to(:user) }
  it { should belong_to(:space) }
end
