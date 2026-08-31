# frozen_string_literal: true

class StaticPagesController < SessionsController
  include TurnstileHelper

  before_action :current_user, except: [:reset_password]
  before_action :no_container, except: :about

  def home
    # Initialize defaults so view partials never encounter nil
    @user_skills = []
    @user_tracks = []
    @volunteer_program_shadowing_scheduled = []
    @volunteer_program_your_tasks = []

    # User-specific data (Only run when a user is signed in)
    user = current_user || @user
    if user
      @volunteer_program_shadowing_scheduled =
        user.shadowing_hours.includes(:space).map do |hours|
          end_time = hours.end_time.strftime('%H:%M')
          formatted_time = "#{I18n.l hours.start_time, format: '%A %H:%M'} - #{end_time}"
          [hours.space.name, formatted_time]
        end

      @volunteer_program_your_tasks =
        begin
          user
            .volunteer_task_joins
            .active
            .order(updated_at: :desc)
            .joins(:volunteer_task)
            .includes(volunteer_task: :space)
            .where(volunteer_task: { status: 'open' })
            .limit(5)
            .map do |task|
              task_name = task.volunteer_task.title
              space_name = task.volunteer_task.space.name
              formatted_time = task.created_at.strftime('%H:%M')
              [task_name, space_name, formatted_time, task.volunteer_task_id]
            end
        rescue StandardError
          []
        end

      @user_skills =
        Certification
          .where(user_id: user.id)
          .joins(training_session: :training)
          .limit(5)
          .pluck('trainings.name_en', 'training_sessions.level')

      # Cached total tracks count
      total_tracks = Rails.cache.fetch('LearningModuleTotalTracks', expires_in: 1.hour) do
        LearningModule.unscope(:order).joins(:training).group('trainings.name_en').count
      end

      @user_tracks =
        user
          .learning_module_tracks
          .includes(learning_module: :training)
          .group_by { |x| x.learning_module.training.name_en }
          .transform_values { |x| x.map(&:status).tally }
          .map do |key, value|
            [key, "#{value['Completed'] || 0}/#{total_tracks[key] || 0}"]
          end
    end

    # Cached Recent Repositories
    @recent_projects =
      Rails.cache.fetch('StaticPagesRecentRepos', expires_in: 10.minutes) do
        Repository
          .public_repos
          .order(created_at: :desc)
          .includes(photos: { image_attachment: [blob: { variant_records: :blob }] })
          .limit(15)
          .to_a
      end

    # Cached Contact Info
    @contact_info =
      Rails.cache.fetch('StaticPagesContactInfo', expires_in: 30.minutes) do
        ContactInfo.where(show_hours: true).order(name: :asc).to_a
      end

    # Cached Workshops (SimpliEvents)
    @workshops =
      Rails.cache.fetch('SimpliEventsRecentEvents', expires_in: 15.minutes, race_condition_ttl: 15.seconds) do
        fetch_simpli_events
      end

    # Cached MakerStore Links
    @makerstore_links =
      Rails.cache.fetch('ShopifyMakerstoreLinks', expires_in: 1.hour, race_condition_ttl: 15.seconds) do
        home_makerstore_links
      end
  end

  # ─── 2. USER-SPECIFIC WIDGETS (Loaded via Background Turbo Frame) ─────────
  def home_user_widgets
    return head :ok unless current_user

    @volunteer_program_shadowing_scheduled =
      current_user.shadowing_hours.includes(:space).map do |hours|
        end_time = hours.end_time.strftime('%H:%M')
        formatted_time = "#{I18n.l hours.start_time, format: '%A %H:%M'} - #{end_time}"
        [hours.space.name, formatted_time]
      end

    @volunteer_program_your_tasks =
      current_user
        .volunteer_task_joins
        .active
        .order(updated_at: :desc)
        .joins(:volunteer_task)
        .includes(volunteer_task: :space)
        .where(volunteer_task: { status: 'open' })
        .limit(5)
        .map do |task|
          task_name = task.volunteer_task.title
          space_name = task.volunteer_task.space.name
          formatted_time = task.created_at.strftime('%H:%M')
          [task_name, space_name, formatted_time, task.volunteer_task_id]
        end

    @user_skills =
      Certification
        .where(user_id: current_user.id)
        .joins(training_session: :training)
        .limit(5)
        .pluck('trainings.name_en', 'training_sessions.level')

    # Cached total tracks (SQL Group Count instead of full table scan)
    total_tracks = Rails.cache.fetch('LearningModuleTotalTracks', expires_in: 1.hour) do
      LearningModule.joins(:training).group('trainings.name_en').count
    end

    @user_tracks =
      current_user
        .learning_module_tracks
        .includes(learning_module: :training)
        .group_by { |x| x.learning_module.training.name_en }
        .transform_values { |x| x.map(&:status).tally }
        .map do |key, value|
          [key, "#{value['Completed'] || 0}/#{total_tracks[key] || 0}"]
        end

    render partial: 'home_user_widgets', layout: false
  end

  def about; end

  def contact
    @contact_info = ContactInfo.all.order(name: :asc)
  end

  def terms_of_service; end

  def hours
    @contact_info = ContactInfo.where(show_hours: true).order(name: :asc)
    respond_to do |format|
      format.html { render :hours }
      format.json do
        render json: @contact_info.as_json(
          include: :opening_hour,
          only: %i[name email address phone_number show_hours opening_hour]
        )
      end
    end
  end

  def open_hours
    calendars = StaffNeededCalendar.where(role: "open_hours").includes(:space)
    all_calendars = calendars.flat_map do |calendar_record|
      helpers.parse_ics_calendar(
        calendar_record.calendar_url,
        name: calendar_record.space&.name || calendar_record.name.presence || "Unnamed Calendar",
        color: calendar_record.color,
      )
    end
    render json: all_calendars
  end

  def calendar; end
  def forgot_password; end
  def get_involved; end
  def resources; end

  def join_team_program
    if signed_in?
      if current_user.programs.exists?(program_type: Program::TEAMS)
        flash[:alert] = 'You are already part of the Teams Program.'
      else
        current_user.programs.create(program_type: Program::TEAMS)
        flash[:notice] = 'You have successfully joined the Teams Program! See below for more information.'
      end
    else
      flash[:alert] = 'You need to sign in to join the Teams Program.'
    end
    redirect_to root_path
  end

  def reset_password
    unless verify_turnstile
      flash.now[:alert] = 'There was a problem with the captcha, please try again.'
      render :forgot_password and return
    end

    if params[:email].blank?
      flash.now[:alert] = 'Please enter an email address.'
      render :forgot_password and return
    end

    User.find_by(email: params[:email].strip.downcase)&.send_password_reset
    flash[:notice] = 'A reset link email has been sent to the email if the account exists.'
    render :forgot_password
  end

  def report_repository
    if signed_in?
      repository = Repository.find(params[:repository_id])
      MsrMailer.repo_report(repository, current_user).deliver_now
      flash[:alert] = 'Repository has been reported'
    else
      flash[:alert] = 'Please login if you wish to report this repository'
    end
    redirect_back(fallback_location: root_path)
  end

  private

  def fetch_simpli_events
    uri = URI('https://simpli.events/api/organizer/44d09ce5-5999-4bd9-82eb-8a9772963223')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 2
    http.read_timeout = 3

    response = http.get(uri.request_uri)
    return [] unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    now_ms = Time.current.to_i * 1000

    data['events']
      .select { |x| x['startTime'] >= now_ms }
      .sort_by { |x| x['startTime'] }
      .take(5)
  rescue StandardError => e
    Rails.logger.error("Failed to fetch SimpliEvents: #{e.message}")
    []
  end

  def home_makerstore_links
    credentials = Rails.application.credentials[Rails.env.to_sym] || {}
    shopify_creds = credentials[:shopify] || {}
    access_token = shopify_creds[:password]
    return [] if access_token.blank?

    shop_url = 'uottawa-makerspace.myshopify.com'
    sess = ShopifyAPI::Auth::Session.new(shop: shop_url, access_token: access_token)
    client = ShopifyAPI::Clients::Graphql::Admin.new(session: sess)

    query = <<~QUERY
      query {
        collections(first: 8) {
          nodes {
            id
            handle
            description
            title
            image {
              url
            }
          }
        }
      }
    QUERY

    items = client.query(query: query)
    if items.code == 200
      items.body.dig('data', 'collections', 'nodes')&.map do |node|
        {
          'title' => node['title'],
          'url' => "https://makerstore.ca/collections/#{node['handle']}",
          'image' => node.dig('image', 'url')
        }
      end || []
    else
      []
    end
  rescue StandardError => e
    Rails.logger.error("Failed to fetch Shopify collections: #{e.message}")
    []
  end
end
