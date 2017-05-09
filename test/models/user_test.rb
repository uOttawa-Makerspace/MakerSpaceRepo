require 'test_helper'

class UserTest < ActiveSupport::TestCase

  context 'user basic info' do
    setup do
      @b = users(:bob)
      should validate_presence_of(:email)
      should validate_presence_of(:password)
    end
  end
end
