require 'test_helper'

class Admin::ReportGeneratorControllerTest < ActionController::TestCase
  setup do
    session[:user_id] = User.find_by(username: "adam").id
    session[:expires_at] = "Sat, 03 Jun 2020 05:01:41 UTC +00:00"
    @request.env['HTTP_REFERER'] =  admin_report_generator_index_url
  end

  test "session is nil at the start" do
    get 'index'
    assert_nil session[:selected_dates]
  end

  test 'date select saves the dates into session' do
    put 'select_date_range', :start => {:year => '2017', :month => '10', :day => '16'},
                             :end => {:year => '2017', :month => '11', :day => '16'}

    assert_not_nil session[:selected_dates]
    assert_equal session[:selected_dates].length , 2
    assert_redirected_to :back
  end

end
