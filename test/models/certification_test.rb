require 'test_helper'

class CertificationTest < ActiveSupport::TestCase

  test "Presence of user_id" do
    cert = certifications(:bob_lathe_1)

    cert.user_id = 777
    assert cert.valid?, "A user is required."
  end

  test "Presence of training_session_id" do
    cert = certifications(:bob_lathe_1)

    cert.training_session_id = 2
    assert cert.valid?, "A training session is required."
  end

  test "Uniqueness of certification" do
    cert = Certification.new(user_id: 1, training_session_id: 1)
    assert cert.invalid?, "Certification already exists."

    cert.training_session_id = 2
    assert cert.valid?
  end

end
