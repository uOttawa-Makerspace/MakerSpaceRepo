require 'rails_helper'

RSpec.describe Staff::MyCalendarController, type: :controller do
  let(:user) { create(:user, :staff) }
  let(:space) { create(:space) }
  let(:staff_space) { create(:staff_space, user: user, space: space, color: '#FF5733') }
  
  before do
    session[:expires_at] = DateTime.tomorrow.end_of_day
    session[:user_id] = user.id
    
    staff_space
    user.update(space_id: space.id)
  end

  describe 'GET #index' do
    let(:user_with_spaces) { create(:user, :staff) }
    let!(:space1) { create(:space) }
    let!(:space2) { create(:space) }
    let!(:staff_space1) { create(:staff_space, user: user_with_spaces, space: space1) }
    let!(:staff_space2) { create(:staff_space, user: user_with_spaces, space: space2) }
    
    before do
      session[:user_id] = user_with_spaces.id
      session[:expires_at] = DateTime.tomorrow.end_of_day
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
     # Should use the user's first accessible space
     expect([space1.id, space2.id]).to include(assigns(:space_id))
    end

    it 'renders with staff_area layout' do
      get :index
      expect(response).to render_template(layout: 'staff_area')
    end
  end

  describe 'GET #json' do
    context 'without space_id parameter' do
      it 'returns bad request error' do
        get :json, params: { id: '' }, format: :json
        
        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)['error']).to eq('Space ID is required')
      end
    end

    context 'with valid space_id' do
      let!(:event) do
        create(:event,
          space: space,
          draft: false,
          start_time: 1.hour.from_now,
          end_time: 3.hours.from_now
        )
      end

      it 'returns events as JSON' do
        get :json, params: { id: space.id }, format: :json
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response).to be_an(Array)
      end

      it 'does not include draft events' do
        draft_event = create(:event, 
          space: space, 
          draft: true,
          start_time: 1.hour.from_now,
          end_time: 2.hours.from_now
        )
        get :json, params: { id: space.id }, format: :json
        
        json_response = JSON.parse(response.body)
        event_ids = json_response.map { |e| e['id'] }
        expect(event_ids).not_to include("event-#{draft_event.id}")
      end

      it 'includes non-draft events within date range' do
        get :json, params: { id: space.id }, format: :json
        
        json_response = JSON.parse(response.body)
        expect(json_response.length).to eq(1)
        expect(json_response.first['id']).to eq("event-#{event.id}")
      end
    end

    context 'with event_type filter' do
      let!(:training_event) do
        create(:event,
          space: space,
          event_type: 'training',
          draft: false,
          start_time: 1.hour.from_now,
          end_time: 3.hours.from_now
        )
      end

      let!(:meeting_event) do
        create(:event,
          space: space,
          event_type: 'meeting',
          draft: false,
          start_time: 1.hour.from_now,
          end_time: 2.hours.from_now
        )
      end

      it 'filters events by event_type' do
        get :json, params: { id: space.id, event_type: 'training' }, format: :json
        
        json_response = JSON.parse(response.body)
        expect(json_response.length).to eq(1)
        expect(json_response.first['extendedProps']['eventType']).to eq('training')
      end
    end

    context 'with user_id filter' do
      let(:assigned_user) { create(:user, :staff) }
      let(:other_user) { create(:user, :staff) }
      
      let!(:assigned_event) do
        create(:event,
          space: space,
          draft: false,
          start_time: 1.hour.from_now,
          end_time: 3.hours.from_now
        )
      end

      let!(:other_event) do
        create(:event,
          space: space,
          draft: false,
          start_time: 1.hour.from_now,
          end_time: 2.hours.from_now
        )
      end

      before do
        create(:event_assignment, event: assigned_event, user: assigned_user)
        create(:event_assignment, event: other_event, user: other_user)
      end

      it 'filters events by assigned user' do
        get :json, params: { id: space.id, user_id: assigned_user.id }, format: :json
        
        json_response = JSON.parse(response.body)
        expect(json_response.length).to eq(1)
        expect(json_response.first['id']).to eq("event-#{assigned_event.id}")
      end

      it 'returns distinct events when user has multiple assignments' do
        create(:event_assignment, event: assigned_event, user: assigned_user)
        
        get :json, params: { id: space.id, user_id: assigned_user.id }, format: :json
        
        json_response = JSON.parse(response.body)
        expect(json_response.length).to eq(1)
      end
    end

    context 'with date range parameters' do
      let!(:past_event) do
        create(:event,
          space: space,
          draft: false,
          start_time: 6.months.ago,
          end_time: 6.months.ago + 1.hour
        )
      end

      let!(:current_event) do
        create(:event,
          space: space,
          draft: false,
          start_time: 1.hour.from_now,
          end_time: 2.hours.from_now
        )
      end

      let!(:future_event) do
        create(:event,
          space: space,
          draft: false,
          start_time: 6.months.from_now,
          end_time: 6.months.from_now + 1.hour
        )
      end

      it 'filters events by custom date range' do
        start_date = 1.week.ago.iso8601
        end_date = 1.week.from_now.iso8601
        
        get :json, params: {
          id: space.id,
          start: start_date,
          end: end_date
        }, format: :json
        
        json_response = JSON.parse(response.body)
        expect(json_response.length).to eq(1)
        expect(json_response.first['id']).to eq("event-#{current_event.id}")
      end

      it 'uses default date range of 3 months when not provided' do
        get :json, params: { id: space.id }, format: :json
        
        json_response = JSON.parse(response.body)
        expect(json_response.length).to eq(1)
        expect(json_response.first['id']).to eq("event-#{current_event.id}")
      end

      it 'handles timezone parsing correctly' do
        start_date = Time.zone.now.iso8601
        end_date = 1.day.from_now.iso8601
        
        expect {
          get :json, params: {
            id: space.id,
            start: start_date,
            end: end_date
          }, format: :json
        }.not_to raise_error
      end
    end

    context 'with recurring events' do
      let!(:recurring_event) do
        create(:event,
          space: space,
          draft: false,
          start_time: 1.day.from_now.beginning_of_week,
          end_time: 1.day.from_now.beginning_of_week + 2.hours,
          recurrence_rule: 'FREQ=WEEKLY;BYDAY=MO;COUNT=4'
        )
      end

      it 'expands weekly recurring events' do
        start_date = 1.day.from_now.beginning_of_week.iso8601
        end_date = 5.weeks.from_now.iso8601
        
        get :json, params: {
          id: space.id,
          start: start_date,
          end: end_date
        }, format: :json
        
        json_response = JSON.parse(response.body)
        expect(json_response.length).to eq(4)
        
        ids = json_response.map { |e| e['id'] }
        expect(ids.uniq.length).to eq(4)
        
        ids.each do |id|
          expect(id).to start_with("event-#{recurring_event.id}")
        end
      end

      it 'handles daily recurrence' do
        daily_event = create(:event,
          space: space,
          draft: false,
          start_time: 2.hours.from_now,
          end_time: 3.hours.from_now,
          recurrence_rule: 'FREQ=DAILY;COUNT=3'
        )

        start_date = Time.zone.now.iso8601
        end_date = 5.days.from_now.iso8601
        
        get :json, params: {
          id: space.id,
          start: start_date,
          end: end_date
        }, format: :json
        
        json_response = JSON.parse(response.body)
        daily_occurrences = json_response.select { |e| e['id'].include?("event-#{daily_event.id}") }
        expect(daily_occurrences.length).to eq(3)
      end

      it 'preserves event duration for recurring events' do
        get :json, params: {
          id: space.id,
          start: 1.day.from_now.beginning_of_week.iso8601,
          end: 5.weeks.from_now.iso8601
        }, format: :json
        
        json_response = JSON.parse(response.body)
        
        json_response.each do |occurrence|
          start_time = Time.zone.parse(occurrence['start'])
          end_time = Time.zone.parse(occurrence['end'])
          duration = end_time - start_time
          
          expect(duration).to eq(2.hours)
        end
      end

      it 'handles RRULE with prefix' do
        event_with_prefix = create(:event,
          space: space,
          draft: false,
          start_time: 1.hour.from_now,
          end_time: 2.hours.from_now,
          recurrence_rule: "RRULE:FREQ=DAILY;COUNT=2"
        )

        get :json, params: { id: space.id }, format: :json
        
        json_response = JSON.parse(response.body)
        occurrences = json_response.select { |e| e['id'].include?("event-#{event_with_prefix.id}") }
        expect(occurrences.length).to eq(2)
      end

      it 'handles RRULE without prefix' do
        event_without_prefix = create(:event,
          space: space,
          draft: false,
          start_time: 1.hour.from_now,
          end_time: 2.hours.from_now,
          recurrence_rule: "FREQ=DAILY;COUNT=2"
        )

        get :json, params: { id: space.id }, format: :json
        
        json_response = JSON.parse(response.body)
        occurrences = json_response.select { |e| e['id'].include?("event-#{event_without_prefix.id}") }
        expect(occurrences.length).to eq(2)
      end

      it 'handles malformed recurrence rules gracefully' do
        invalid_event = create(:event,
          space: space,
          draft: false,
          start_time: 1.hour.from_now,
          end_time: 2.hours.from_now,
          recurrence_rule: 'INVALID_RULE'
        )

        expect {
          get :json, params: { id: space.id }, format: :json
        }.not_to raise_error
        
        json_response = JSON.parse(response.body)
        event_data = json_response.find { |e| e['id'] == "event-#{invalid_event.id}" }
        expect(event_data).to be_present
      end

      it 'handles empty recurrence rules gracefully' do
        event_with_empty_rule = create(:event,
          space: space,
          draft: false,
          start_time: 1.hour.from_now,
          end_time: 2.hours.from_now,
          recurrence_rule: ''
        )

        expect {
          get :json, params: { id: space.id }, format: :json
        }.not_to raise_error
      end
    end

    context 'event formatting' do
      let(:assigned_user) { create(:user, :staff, name: 'John Doe') }
      let(:training) { create(:training) }
      let(:course_name) { create(:course_name) }
      
      let!(:training_event) do
        create(:event,
          space: space,
          draft: false,
          event_type: 'training',
          title: 'Training',
          start_time: 1.hour.from_now,
          end_time: 3.hours.from_now,
          training: training,
          course_name: course_name,
          language: 'English'
        )
      end

      before do
        create(:event_assignment, event: training_event, user: assigned_user)
      end

      it 'formats training events with assignments correctly' do
        get :json, params: { id: space.id }, format: :json
        
        json_response = JSON.parse(response.body)
        event_data = json_response.first
        
        expect(event_data['title']).to include(training.name_en)
        expect(event_data['title']).to include(course_name.name)
        expect(event_data['title']).to include('English')
        expect(event_data['title']).to include('John Doe')
      end

      it 'formats non-training events correctly' do
        meeting_event = create(:event,
          space: space,
          draft: false,
          event_type: 'meeting',
          title: 'Team Meeting',
          start_time: 1.hour.from_now,
          end_time: 2.hours.from_now
        )

        get :json, params: { id: space.id }, format: :json
        
        json_response = JSON.parse(response.body)
        event_data = json_response.find { |e| e['id'] == "event-#{meeting_event.id}" }
        
        expect(event_data['title']).to eq('Team Meeting')
      end

      it 'creates gradient background for multiple assignments' do
        user2 = create(:user, :staff, name: 'Jane Smith')
        
        # Ensure we control the staff_space colors
        ss1 = StaffSpace.find_or_create_by(user: assigned_user, space: space)
        ss1.update!(color: '#FF5733')
        
        create(:event_assignment, event: training_event, user: user2)
        
        ss2 = StaffSpace.find_or_create_by(user: user2, space: space)
        ss2.update!(color: '#00FF00')

        get :json, params: { id: space.id }, format: :json
        
        json_response = JSON.parse(response.body)
        event_data = json_response.first
        
        expect(event_data['extendedProps']['background']).to include('linear-gradient')
        
        # Check both colors are in the gradient
        background = event_data['extendedProps']['background']
        expect(background).to include('#FF5733')
        expect(background).to include('#00FF00')
      end

      it 'uses default color when staff_space color not found' do
        user_without_color = create(:user, :staff)
        event_without_color = create(:event,
          space: space,
          draft: false,
          start_time: 1.hour.from_now,
          end_time: 2.hours.from_now
        )
        create(:event_assignment, event: event_without_color, user: user_without_color)

        get :json, params: { id: space.id }, format: :json
        
        json_response = JSON.parse(response.body)
        event_data = json_response.find { |e| e['id'] == "event-#{event_without_color.id}" }
        
        expect(event_data['extendedProps']['background']).to include('#3788d8')
      end

      it 'sets hasCurrentUser flag to true when current user is assigned' do
        create(:event_assignment, event: training_event, user: user)

        get :json, params: { id: space.id }, format: :json
        
        json_response = JSON.parse(response.body)
        event_data = json_response.first
        
        expect(event_data['extendedProps']['hasCurrentUser']).to be true
      end

      it 'sets hasCurrentUser flag to false when current user is not assigned' do
        get :json, params: { id: space.id }, format: :json
        
        json_response = JSON.parse(response.body)
        event_data = json_response.first
        
        expect(event_data['extendedProps']['hasCurrentUser']).to be false
      end

      it 'formats ISO8601 dates correctly' do
        get :json, params: { id: space.id }, format: :json
        
        json_response = JSON.parse(response.body)
        event_data = json_response.first
        
        expect(event_data['start']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
        expect(event_data['end']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end

      it 'detects all-day events correctly' do
        all_day_event = create(:event,
          space: space,
          draft: false,
          start_time: 1.day.from_now.beginning_of_day,
          end_time: 1.day.from_now.beginning_of_day + 1.day
        )

        get :json, params: { id: space.id }, format: :json
        
        json_response = JSON.parse(response.body)
        event_data = json_response.find { |e| e['id'] == "event-#{all_day_event.id}" }
        
        expect(event_data['allDay']).to be true
      end

      it 'sets allDay to false for partial day events' do
        partial_day_event = create(:event,
          space: space,
          draft: false,
          start_time: 1.day.from_now.beginning_of_day + 9.hours,
          end_time: 1.day.from_now.beginning_of_day + 17.hours
        )

        get :json, params: { id: space.id }, format: :json
        
        json_response = JSON.parse(response.body)
        event_data = json_response.find { |e| e['id'] == "event-#{partial_day_event.id}" }
        
        expect(event_data['allDay']).to be false
      end

      it 'includes all required extendedProps fields' do
        get :json, params: { id: space.id }, format: :json
        
        json_response = JSON.parse(response.body)
        event_data = json_response.first
        
        expect(event_data['extendedProps']).to include(
          'name',
          'draft',
          'description',
          'eventType',
          'hasCurrentUser',
          'background'
        )
      end

      it 'handles events without assignments' do
        unassigned_event = create(:event,
          space: space,
          draft: false,
          title: 'Unassigned Event',
          start_time: 1.hour.from_now,
          end_time: 2.hours.from_now
        )

        get :json, params: { id: space.id }, format: :json
        
        json_response = JSON.parse(response.body)
        event_data = json_response.find { |e| e['id'] == "event-#{unassigned_event.id}" }
        
        expect(event_data['title']).to eq('Unassigned Event')
        expect(event_data['extendedProps']['background']).to eq('#3788d8')
      end
    end

    context 'combined filters' do
      let(:user1) { create(:user, :staff) }
      let(:user2) { create(:user, :staff) }
      
      let!(:training_for_user1) do
        event = create(:event,
          space: space,
          draft: false,
          event_type: 'training',
          start_time: 2.hours.from_now,
          end_time: 4.hours.from_now
        )
        create(:event_assignment, event: event, user: user1)
        event
      end

      let!(:meeting_for_user1) do
        event = create(:event,
          space: space,
          draft: false,
          event_type: 'meeting',
          start_time: 1.day.from_now,
          end_time: 1.day.from_now + 1.hour
        )
        create(:event_assignment, event: event, user: user1)
        event
      end

      let!(:training_for_user2) do
        event = create(:event,
          space: space,
          draft: false,
          event_type: 'training',
          start_time: 2.days.from_now,
          end_time: 2.days.from_now + 2.hours
        )
        create(:event_assignment, event: event, user: user2)
        event
      end

      it 'filters by both event_type and user_id' do
        get :json, params: {
          id: space.id,
          event_type: 'training',
          user_id: user1.id
        }, format: :json
        
        json_response = JSON.parse(response.body)
        expect(json_response.length).to eq(1)
        expect(json_response.first['id']).to eq("event-#{training_for_user1.id}")
      end

      it 'filters by event_type, user_id, and date range' do
        start_date = 1.hour.from_now.iso8601
        end_date = 1.5.days.from_now.iso8601

        get :json, params: {
          id: space.id,
          event_type: 'training',
          user_id: user1.id,
          start: start_date,
          end: end_date
        }, format: :json
        
        json_response = JSON.parse(response.body)
        expect(json_response.length).to eq(1)
      end
    end

    context 'edge cases' do
      it 'handles events with nil description' do
        event_without_description = create(:event,
          space: space,
          draft: false,
          description: nil,
          start_time: 1.hour.from_now,
          end_time: 2.hours.from_now
        )

        expect {
          get :json, params: { id: space.id }, format: :json
        }.not_to raise_error
      end

      it 'handles events with very long titles' do
        long_title = 'A' * 500
        event_with_long_title = create(:event,
          space: space,
          draft: false,
          title: long_title,
          start_time: 1.hour.from_now,
          end_time: 2.hours.from_now
        )

        get :json, params: { id: space.id }, format: :json
        
        json_response = JSON.parse(response.body)
        event_data = json_response.find { |e| e['id'] == "event-#{event_with_long_title.id}" }
        expect(event_data['title']).to eq(long_title)
      end

      it 'returns empty array when no events match filters' do
        get :json, params: {
          id: space.id,
          event_type: 'nonexistent_type'
        }, format: :json
        
        json_response = JSON.parse(response.body)
        expect(json_response).to eq([])
      end

      it 'handles space with no events' do
        empty_space = create(:space)
        create(:staff_space, user: user, space: empty_space)

        get :json, params: { id: empty_space.id }, format: :json
        
        json_response = JSON.parse(response.body)
        expect(json_response).to eq([])
      end
    end
  end
end