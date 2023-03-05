require "rails_helper"

RSpec.describe ShadowingHour, type: :model do
  it { should belong_to(:user).without_validating_presence }
  it { should belong_to(:space).without_validating_presence }
end
