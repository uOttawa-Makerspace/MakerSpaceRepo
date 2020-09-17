require 'rails_helper'

RSpec.describe Admin::ReportGeneratorController, type: :controller do

  describe 'GET /index' do

    context 'logged in as admin' do

      it 'should get a 200' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        get :index
      end

    end

    context 'logged in as regular user' do

      it 'should redirect user to root' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :index
        expect(response).to redirect_to root_path
      end

    end

  end

  describe "GET /popular_hours" do

    context "logged in as admin" do

      it 'should get a 200' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        get :popular_hours
      end

    end

    context "logged in as regular user" do

      it 'should redirect user to root' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :popular_hours
        expect(response).to redirect_to root_path
      end

    end

  end

  describe "post /generate" do

    before(:each) do
      admin = create(:user, :admin)
      session[:user_id] = admin.id
      session[:expires_at] = Time.zone.now + 10000
      Space.create(name: 'Makerspace') if Space.find_by(name: 'Makerspace').blank?
      Space.create(name: 'MTC') if Space.find_by(name: 'MTC').blank?
    end

    context 'generate Certifications' do

      it 'should get report for semester' do
        post :generate, params: {range_type: 'semester', term: 'winter', year: DateTime.now.year, type: 'certifications'}
        expect(response.header['Content-Type']).to eq('application/xlsx')
        expect(response.header['Content-Disposition']).to include("certifications_#{DateTime.new(DateTime.now.year, 1, 1).strftime('%Y-%m-%d')}_#{DateTime.new(DateTime.now.year, 4, 30).strftime('%Y-%m-%d')}.xlsx")
      end

      it 'should get report for date range' do
        post :generate, params: {range_type: 'date_range', from_date: 1.week.ago.beginning_of_week.strftime('%Y-%m-%d'), to_date: 1.week.ago.end_of_week.strftime('%Y-%m-%d'), type: 'certifications'}
        expect(response.header['Content-Type']).to eq('application/xlsx')
        expect(response.header['Content-Disposition']).to include("certifications_#{1.week.ago.beginning_of_week.strftime("%Y-%m-%d")}_#{1.week.ago.end_of_week.strftime("%Y-%m-%d")}.xlsx")
      end

      it 'should fail getting the report (year wrong)' do
        post :generate, params: {range_type: 'semester', term: 'winter', year: -2020, type: 'certifications'}
        expect(response).to have_http_status(400)
      end

      it 'should fail getting the report (bad term)' do
        post :generate, params: {range_type: 'semester', term: 'wintersummer', year: DateTime.now.year, type: 'certifications'}
        expect(response).to have_http_status(400)
      end

      it 'should fail getting the report (bad term)' do
        post :generate, params: {range_type: 'semester', term: 'summer', year: DateTime.now.year, type: 'certificationssssss'}
        expect(response).to have_http_status(400)
      end

    end

    context 'generate New Projects' do

      it 'should get report for semester' do
        post :generate, params: {range_type: 'semester', term: 'summer', year: DateTime.now.year, type: 'new_projects'}
        expect(response.header['Content-Type']).to eq('application/xlsx')
        expect(response.header['Content-Disposition']).to include("new_projects_#{DateTime.new(DateTime.now.year, 5, 1).strftime('%Y-%m-%d')}_#{DateTime.new(DateTime.now.year, 8, 31).strftime('%Y-%m-%d')}.xlsx")
      end

      it 'should get report for date range' do
        post :generate, params: {range_type: 'date_range', from_date: 4.week.ago.beginning_of_week.strftime('%Y-%m-%d'), to_date: 2.week.ago.end_of_week.strftime('%Y-%m-%d'), type: 'new_projects'}
        expect(response.header['Content-Type']).to eq('application/xlsx')
        expect(response.header['Content-Disposition']).to include("new_projects_#{4.week.ago.beginning_of_week.strftime("%Y-%m-%d")}_#{2.week.ago.end_of_week.strftime("%Y-%m-%d")}.xlsx")
      end

    end

    context 'generate New Users' do

      it 'should get report for semester' do
        post :generate, params: {range_type: 'semester', term: 'fall', year: DateTime.now.year, type: 'new_users'}
        expect(response.header['Content-Type']).to eq('application/xlsx')
        expect(response.header['Content-Disposition']).to include("new_users_#{DateTime.new(DateTime.now.year, 9, 1).strftime('%Y-%m-%d')}_#{DateTime.new(DateTime.now.year, 12, 31).strftime('%Y-%m-%d')}.xlsx")
      end

      it 'should get report for date range' do
        post :generate, params: {range_type: 'date_range', from_date: 8.week.ago.beginning_of_week.strftime('%Y-%m-%d'), to_date: 3.week.ago.end_of_week.strftime('%Y-%m-%d'), type: 'new_users'}
        expect(response.header['Content-Type']).to eq('application/xlsx')
        expect(response.header['Content-Disposition']).to include("new_users_#{8.week.ago.beginning_of_week.strftime("%Y-%m-%d")}_#{3.week.ago.end_of_week.strftime("%Y-%m-%d")}.xlsx")
      end

    end

    context 'generate Trainings' do

      it 'should get report for semester' do
        post :generate, params: {range_type: 'semester', term: 'winter', year: DateTime.now.year, type: 'trainings'}
        expect(response.header['Content-Type']).to eq('application/xlsx')
        expect(response.header['Content-Disposition']).to include("trainings_#{DateTime.new(DateTime.now.year, 1, 1).strftime('%Y-%m-%d')}_#{DateTime.new(DateTime.now.year, 4, 30).strftime('%Y-%m-%d')}.xlsx")
      end

      it 'should get report for date range' do
        post :generate, params: {range_type: 'date_range', from_date: 1.week.ago.beginning_of_week.strftime('%Y-%m-%d'), to_date: 1.week.ago.end_of_week.strftime('%Y-%m-%d'), type: 'trainings'}
        expect(response.header['Content-Type']).to eq('application/xlsx')
        expect(response.header['Content-Disposition']).to include("trainings_#{1.week.ago.beginning_of_week.strftime("%Y-%m-%d")}_#{1.week.ago.end_of_week.strftime("%Y-%m-%d")}.xlsx")
      end

    end

    context 'generate Training Attendees' do

      it 'should get report for semester' do
        post :generate, params: {range_type: 'semester', term: 'summer', year: DateTime.now.year, type: 'training_attendees'}
        expect(response.header['Content-Type']).to eq('application/xlsx')
        expect(response.header['Content-Disposition']).to include("training_attendees_#{DateTime.new(DateTime.now.year, 5, 1).strftime('%Y-%m-%d')}_#{DateTime.new(DateTime.now.year, 8, 31).strftime('%Y-%m-%d')}.xlsx")
      end

      it 'should get report for date range' do
        post :generate, params: {range_type: 'date_range', from_date: 4.week.ago.beginning_of_week.strftime('%Y-%m-%d'), to_date: 2.week.ago.end_of_week.strftime('%Y-%m-%d'), type: 'training_attendees'}
        expect(response.header['Content-Type']).to eq('application/xlsx')
        expect(response.header['Content-Disposition']).to include("training_attendees_#{4.week.ago.beginning_of_week.strftime("%Y-%m-%d")}_#{2.week.ago.end_of_week.strftime("%Y-%m-%d")}.xlsx")
      end

    end

    context 'generate Visitors' do

      it 'should get report for semester' do
        post :generate, params: {range_type: 'semester', term: 'fall', year: DateTime.now.year, type: 'visitors'}
        expect(response.header['Content-Type']).to eq('application/xlsx')
        expect(response.header['Content-Disposition']).to include("visitors_#{DateTime.new(DateTime.now.year, 9, 1).strftime('%Y-%m-%d')}_#{DateTime.new(DateTime.now.year, 12, 31).strftime('%Y-%m-%d')}.xlsx")
      end

      it 'should get report for date range' do
        post :generate, params: {range_type: 'date_range', from_date: 7.week.ago.beginning_of_week.strftime('%Y-%m-%d'), to_date: 3.week.ago.end_of_week.strftime('%Y-%m-%d'), type: 'visitors'}
        expect(response.header['Content-Type']).to eq('application/xlsx')
        expect(response.header['Content-Disposition']).to include("visitors_#{7.week.ago.beginning_of_week.strftime("%Y-%m-%d")}_#{3.week.ago.end_of_week.strftime("%Y-%m-%d")}.xlsx")
      end

    end

    context 'generate Visits by Hour' do

      it 'should get report for semester' do
        post :generate, params: {range_type: 'semester', term: 'winter', year: DateTime.now.year, type: 'visits_by_hour'}
        expect(response.header['Content-Type']).to eq('application/xlsx')
        expect(response.header['Content-Disposition']).to include("visits_by_hour_#{DateTime.new(DateTime.now.year, 1, 1).strftime('%Y-%m-%d')}_#{DateTime.new(DateTime.now.year, 4, 30).strftime('%Y-%m-%d')}.xlsx")
      end

      it 'should get report for date range' do
        post :generate, params: {range_type: 'date_range', from_date: 1.week.ago.beginning_of_week.strftime('%Y-%m-%d'), to_date: 1.week.ago.end_of_week.strftime('%Y-%m-%d'), type: 'visits_by_hour'}
        expect(response.header['Content-Type']).to eq('application/xlsx')
        expect(response.header['Content-Disposition']).to include("visits_by_hour_#{1.week.ago.beginning_of_week.strftime("%Y-%m-%d")}_#{1.week.ago.end_of_week.strftime("%Y-%m-%d")}.xlsx")
      end

    end

  end

end




