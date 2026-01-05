require 'rails_helper'

RSpec.describe Staff::MyCalendarController, type: :controller do
  # Share expensive setup across ALL tests
  before(:all) do
    @space = create(:space)
    @user = create(:user, :staff, space_id: @space.id)
    @staff_space = create(:staff_space, user: @user, space: @space, color: '#FF5733')
    
    # Create shared events once for read-only tests
    @base_event = create(:event,
      space: @space,
      draft: false,
      start_time: 1.hour.from_now,
      end_time: 3.hours.from_now
    )
    
    @past_event = create(:event,
      space: @space,
      draft: false,
      start_time: 6.months.ago,
      end_time: 6.months.ago + 1.hour
    )
    
    @future_event = create(:event,
      space: @space,
      draft: false,
      start_time: 6.months.from_now,
      end_time: 6.months.from_now + 1.hour
    )
  end
  
  after(:all) do
    DatabaseCleaner.clean_with(:truncation)
  end
  
  before(:each) do
    session[:expires_at] = DateTime.tomorrow.end_of_day
    session[:user_id] = @user.id
  end

  describe 'GET #index' do
    # Only create data needed for mutation tests
    let!(:space1) { create(:space) }
    let!(:space2) { create(:space) }
    let(:user_with_spaces) { create(:user, :staff) }
    
    before do
      create(:staff_space, user: user_with_spaces, space: space1)
      create(:staff_space, user: user_with_spaces, space: space2)
      session[:user_id] = user_with_spaces.id
    end

    it 'assigns spaces accessible by current user' do
      get :index
      expect(assigns(:spaces)).to match_array([space1, space2])
    end

    it 'assigns default space_id from user' do
      user_with_spaces.update(space_id: space1.id)
      get :index
      expect(assigns(:space_id)).to eq(space1.id)
    end

    it 'uses first space if user has no space_id' do
      user_with_spaces.update(space_id: nil)
      get :index
      expect([space1.id, space2.id]).to include(assigns(:space_id))
    end

    it 'renders with staff_area layout' do
      get :index
      expect(response).to render_template(layout: 'staff_area')
    end
  end

  describe 'GET #json' do
    it 'returns bad request error without space_id' do
      get :json, params: { id: '' }, format: :json
      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)['error']).to eq('Space ID is required')
    end

    # Group basic functionality tests to reuse setup
    context 'basic event retrieval' do
      it 'returns events as JSON and excludes drafts' do
        draft_event = create(:event, space: @space, draft: true, start_time: 1.hour.from_now, end_time: 2.hours.from_now)
        
        get :json, params: { id: @space.id }, format: :json
        
        json_response = JSON.parse(response.body)
        expect(response).to have_http_status(:success)
        expect(json_response).to be_an(Array)
        
        event_ids = json_response.map { |e| e['id'] }
        expect(event_ids).not_to include("event-#{draft_event.id}")
        expect(event_ids).to include("event-#{@base_event.id}")
      end
    end

    context 'filtering' do
      before(:all) do
        @training_event = create(:event, space: @space, event_type: 'training', draft: false, start_time: 1.hour.from_now, end_time: 3.hours.from_now)
        @meeting_event = create(:event, space: @space, event_type: 'meeting', draft: false, start_time: 1.hour.from_now, end_time: 2.hours.from_now)
        
        @assigned_user = create(:user, :staff)
        @other_user = create(:user, :staff)
        
        @assigned_event = create(:event, space: @space, draft: false, start_time: 1.hour.from_now, end_time: 3.hours.from_now)
        @other_event = create(:event, space: @space, draft: false, start_time: 1.hour.from_now, end_time: 2.hours.from_now)
        
        create(:event_assignment, event: @assigned_event, user: @assigned_user)
        create(:event_assignment, event: @other_event, user: @other_user)
      end

      it 'filters events by event_type' do
        get :json, params: { id: @space.id, event_type: 'training' }, format: :json
        json_response = JSON.parse(response.body)
        training_events = json_response.select { |e| e['extendedProps']['eventType'] == 'training' }
        expect(training_events.length).to be >= 1
      end

      it 'filters events by assigned user and handles duplicates' do
        get :json, params: { id: @space.id, user_id: @assigned_user.id }, format: :json
        
        json_response = JSON.parse(response.body)
        expect(json_response.map { |e| e['id'] }).to include("event-#{@assigned_event.id}")
        expect(json_response.map { |e| e['id'] }).not_to include("event-#{@other_event.id}")
      end

      it 'combines event_type and user_id filters' do
        create(:event_assignment, event: @training_event, user: @assigned_user)
        
        get :json, params: { id: @space.id, event_type: 'training', user_id: @assigned_user.id }, format: :json
        
        json_response = JSON.parse(response.body)
        expect(json_response.map { |e| e['id'] }).to include("event-#{@training_event.id}")
      end
    end

    context 'date ranges' do
      it 'filters by custom date range and uses default 3-month range' do
        # Test custom range
        start_date = 1.week.ago.iso8601
        end_date = 1.week.from_now.iso8601
        
        get :json, params: { id: @space.id, start: start_date, end: end_date }, format: :json
        json_response = JSON.parse(response.body)
        expect(json_response.map { |e| e['id'] }).to include("event-#{@base_event.id}")
        expect(json_response.map { |e| e['id'] }).not_to include("event-#{@past_event.id}")
        
        # Test default range (reuse request)
        get :json, params: { id: @space.id }, format: :json
        json_response = JSON.parse(response.body)
        expect(json_response.map { |e| e['id'] }).to include("event-#{@base_event.id}")
      end

      it 'handles timezone parsing' do
        expect {
          get :json, params: {
            id: @space.id,
            start: Time.zone.now.iso8601,
            end: 1.day.from_now.iso8601
          }, format: :json
        }.not_to raise_error
      end
    end

    context 'recurring events' do
      before(:all) do
        @weekly_event = create(:event,
          space: @space,
          draft: false,
          start_time: 1.day.from_now.beginning_of_week,
          end_time: 1.day.from_now.beginning_of_week + 2.hours,
          recurrence_rule: 'FREQ=WEEKLY;BYDAY=MO;COUNT=4'
        )
        
        @daily_event = create(:event,
          space: @space,
          draft: false,
          start_time: 2.hours.from_now,
          end_time: 3.hours.from_now,
          recurrence_rule: 'FREQ=DAILY;COUNT=3'
        )
      end

      it 'expands weekly recurring events with correct duration' do
        start_date = 1.day.from_now.beginning_of_week.iso8601
        end_date = 5.weeks.from_now.iso8601
        
        get :json, params: { id: @space.id, start: start_date, end: end_date }, format: :json
        
        json_response = JSON.parse(response.body)
        weekly_occurrences = json_response.select { |e| e['id'].include?("event-#{@weekly_event.id}") }
        
        expect(weekly_occurrences.length).to eq(4)
        
        # Check duration preservation
        weekly_occurrences.each do |occurrence|
          duration = Time.zone.parse(occurrence['end']) - Time.zone.parse(occurrence['start'])
          expect(duration).to eq(2.hours)
        end
      end

      it 'handles daily recurrence' do
        get :json, params: {
          id: @space.id,
          start: Time.zone.now.iso8601,
          end: 5.days.from_now.iso8601
        }, format: :json
        
        json_response = JSON.parse(response.body)
        daily_occurrences = json_response.select { |e| e['id'].include?("event-#{@daily_event.id}") }
        expect(daily_occurrences.length).to eq(3)
      end

      it 'handles RRULE with and without prefix' do
        event_with_prefix = create(:event, space: @space, draft: false, start_time: 1.hour.from_now, end_time: 2.hours.from_now, recurrence_rule: "RRULE:FREQ=DAILY;COUNT=2")
        event_without_prefix = create(:event, space: @space, draft: false, start_time: 1.hour.from_now, end_time: 2.hours.from_now, recurrence_rule: "FREQ=DAILY;COUNT=2")

        get :json, params: { id: @space.id }, format: :json
        json_response = JSON.parse(response.body)
        
        expect(json_response.select { |e| e['id'].include?("event-#{event_with_prefix.id}") }.length).to eq(2)
        expect(json_response.select { |e| e['id'].include?("event-#{event_without_prefix.id}") }.length).to eq(2)
      end

      it 'handles malformed and empty recurrence rules' do
        create(:event, space: @space, draft: false, start_time: 1.hour.from_now, end_time: 2.hours.from_now, recurrence_rule: 'INVALID_RULE')
        create(:event, space: @space, draft: false, start_time: 1.hour.from_now, end_time: 2.hours.from_now, recurrence_rule: '')

        expect {
          get :json, params: { id: @space.id }, format: :json
        }.not_to raise_error
      end
    end

    context 'event formatting' do
      before(:all) do
        @assigned_user = create(:user, :staff, name: 'John Doe')
        @training = create(:training)
        @course_name = create(:course_name)
        
        @training_event = create(:event,
          space: @space,
          draft: false,
          event_type: 'training',
          title: 'Training',
          start_time: 1.hour.from_now,
          end_time: 3.hours.from_now,
          training: @training,
          course_name: @course_name,
          language: 'English'
        )
        
        create(:event_assignment, event: @training_event, user: @assigned_user)
        
        @ss1 = StaffSpace.find_or_create_by(user: @assigned_user, space: @space)
        @ss1.update!(color: '#FF5733')
      end

      it 'formats training events correctly with all required fields' do
        get :json, params: { id: @space.id }, format: :json
        
        event_data = JSON.parse(response.body).find { |e| e['id'] == "event-#{@training_event.id}" }
        
        expect(event_data['title']).to include(@training.name_en)
        expect(event_data['title']).to include(@course_name.name)
        expect(event_data['title']).to include('English')
        expect(event_data['title']).to include('John Doe')
        
        # Check all required extendedProps in one assertion
        expect(event_data['extendedProps']).to include('name', 'draft', 'description', 'eventType', 'hasCurrentUser', 'background')
        expect(event_data['start']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end

      it 'creates gradient for multiple assignments and uses default color' do
        user2 = create(:user, :staff, name: 'Jane Smith')
        create(:event_assignment, event: @training_event, user: user2)
        ss2 = StaffSpace.find_or_create_by(user: user2, space: @space)
        ss2.update!(color: '#00FF00')

        get :json, params: { id: @space.id }, format: :json
        event_data = JSON.parse(response.body).find { |e| e['id'] == "event-#{@training_event.id}" }
        
        expect(event_data['extendedProps']['background']).to include('linear-gradient', '#FF5733', '#00FF00')
        
        # Test default color
        user_without_color = create(:user, :staff)
        event_without_color = create(:event, space: @space, draft: false, start_time: 1.hour.from_now, end_time: 2.hours.from_now)
        create(:event_assignment, event: event_without_color, user: user_without_color)

        get :json, params: { id: @space.id }, format: :json
        default_event = JSON.parse(response.body).find { |e| e['id'] == "event-#{event_without_color.id}" }
        expect(default_event['extendedProps']['background']).to include('#3788d8')
      end

      it 'sets hasCurrentUser flag correctly' do
        create(:event_assignment, event: @base_event, user: @user)
        
        get :json, params: { id: @space.id }, format: :json
        json = JSON.parse(response.body)
        
        assigned = json.find { |e| e['id'] == "event-#{@base_event.id}" }
        expect(assigned['extendedProps']['hasCurrentUser']).to be true
        
        unassigned = json.find { |e| e['id'] == "event-#{@training_event.id}" }
        expect(unassigned['extendedProps']['hasCurrentUser']).to be false
      end

      it 'detects all-day events correctly' do
        all_day = create(:event, space: @space, draft: false, start_time: 1.day.from_now.beginning_of_day, end_time: 1.day.from_now.beginning_of_day + 1.day)
        partial_day = create(:event, space: @space, draft: false, start_time: 1.day.from_now.beginning_of_day + 9.hours, end_time: 1.day.from_now.beginning_of_day + 17.hours)

        get :json, params: { id: @space.id }, format: :json
        json = JSON.parse(response.body)
        
        expect(json.find { |e| e['id'] == "event-#{all_day.id}" }['allDay']).to be true
        expect(json.find { |e| e['id'] == "event-#{partial_day.id}" }['allDay']).to be false
      end

      it 'formats non-training events and handles unassigned events' do
        meeting = create(:event, space: @space, draft: false, event_type: 'meeting', title: 'Team Meeting', start_time: 1.hour.from_now, end_time: 2.hours.from_now)
        unassigned = create(:event, space: @space, draft: false, title: 'Unassigned Event', start_time: 1.hour.from_now, end_time: 2.hours.from_now)

        get :json, params: { id: @space.id }, format: :json
        json = JSON.parse(response.body)
        
        expect(json.find { |e| e['id'] == "event-#{meeting.id}" }['title']).to eq('Team Meeting')
        expect(json.find { |e| e['id'] == "event-#{unassigned.id}" }['extendedProps']['background']).to eq('#3788d8')
      end
    end

    context 'edge cases' do
      it 'handles nil description, long titles, and empty results' do
        create(:event, space: @space, draft: false, description: nil, start_time: 1.hour.from_now, end_time: 2.hours.from_now)
        long_title_event = create(:event, space: @space, draft: false, title: 'A' * 500, start_time: 1.hour.from_now, end_time: 2.hours.from_now)

        expect { get :json, params: { id: @space.id }, format: :json }.not_to raise_error
        
        json = JSON.parse(response.body)
        expect(json.find { |e| e['id'] == "event-#{long_title_event.id}" }['title'].length).to eq(500)
        
        # Empty results
        get :json, params: { id: @space.id, event_type: 'nonexistent' }, format: :json
        expect(JSON.parse(response.body)).to eq([])
        
        # Space with no events
        empty_space = create(:space)
        create(:staff_space, user: @user, space: empty_space)
        get :json, params: { id: empty_space.id }, format: :json
        expect(JSON.parse(response.body)).to eq([])
      end
    end
  end
end