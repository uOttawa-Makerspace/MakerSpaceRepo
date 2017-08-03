require 'test_helper'

class CertificationTest < ActiveSupport::TestCase

  test "Presence of user" do
    cert = certifications(:bob_lathe_1)

    cert.user_id = nil
    assert cert.invalid?, "A user is required."
      
    cert.user_id = 1
    assert cert.valid?, "A user is required."
  end

end
