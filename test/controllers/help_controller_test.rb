# frozen_string_literal: true

require 'test_helper'

class HelpControllerTest < ActionController::TestCase
  test 'user can submit issue reports' do
    put :send_email, params: { name: 'Julia', email: 'julia@gmail.com', subject: 'issue', comments: 'photo upload not working' }

    assert_equal flash[:notice], 'Email successfuly send. You will be contacted soon.'
    assert_redirected_to root_path
  end
end
