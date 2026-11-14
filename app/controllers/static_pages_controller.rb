# frozen_string_literal: true

class StaticPagesController < SessionsController
  include TurnstileHelper
  include CalendarWindowed

  before_action :current_user, except: [:reset_password]
  before_action :no_container, except: :about

  def home
    # Initialize defaults so view partials never encounter nil
    @user_skills = []
    @user_tracks = []
    @volunteer_program_shadowing_scheduled = []
    @volunteer_program_your_tasks = []
    @hours_calendars = StaffNeededCalendar.open_hours

    # User-specific data (Only run when a user is signed in)
    user = current_user || @user
    load_member_sections(user) if user

    @recent_projects = cached_recent_projects
    @contact_info = cached_contact_info
    @workshops = cached_workshops
    @makerstore_links = cached_makerstore_links
  end

  def about; end

  def contact
    @contact_info = ContactInfo.all.order(name: :asc)
  end

  def terms_of_service; end

  def hours
    @contact_info = ContactInfo.where(show_hours: true).order(name: :asc)
    @hours_calendars = StaffNeededCalendar.open_hours
    respond_to do |format|
      format.html do
        @contact_info = @contact_info.includes(:opening_hours)
        render :hours
      end
      format.json do
        render json: @contact_info.as_json(
          include: :opening_hours,
          only: %i[name email address phone_number show_hours]
        )
      end
    end
  end

  # The opening hours of the spaces: the occurrences in the range the calendar shows (CalendarWindow), or in the
  # current week when no range is given.
  def open_hours
    window = CalendarWindow.from_params(params)
    window = CalendarWindow.week_of(Time.current) if window == CalendarWindow::ALL
    render json: StaffNeededCalendar.open_hours.flat_map { |calendar| calendar.feed_sources(window, name: calendar.hours_name) }
  end

  def calendar; end
  def forgot_password; end
  def get_involved; end
  def resources; end

  def join_team_program
    if signed_in?
      if Program.join(current_user, Program::TEAMS)
        flash[:notice] = 'You have successfully joined the Teams Program! See below for more information.'
      else
        flash[:alert] = 'You are already part of the Teams Program.'
      end
    else
      flash[:alert] = 'You need to sign in to join the Teams Program.'
    end
    redirect_to root_path
  end

  RESET_PASSWORD_NOTICE = 'A reset link email has been sent to the email if the account exists.'

  rate_limit to: 30, within: 1.hour, only: :reset_password, name: 'reset-ip',
             by: -> { request.remote_ip }, with: -> { reset_password_response }

  def reset_password
    unless verify_turnstile
      flash.now[:alert] = 'There was a problem with the captcha, please try again.'
      render :forgot_password and return
    end

    if params[:email].blank?
      flash.now[:alert] = 'Please enter an email address.'
      render :forgot_password and return
    end

    email = params[:email].to_s.strip.downcase
    user = User.find_by(email: email) if email.length <= 254
    user.send_password_reset if user && mail_budget_left?('reset', email)
    reset_password_response
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

  def load_member_sections(user)
    @volunteer_program_shadowing_scheduled = shadowing_shift_entries(user)
    @volunteer_program_your_tasks = open_task_entries(user)
    @user_skills = skill_entries(user)
    @user_tracks = track_progress_entries(user)
  end

  def open_task_entries(user)
    user
      .volunteer_task_joins
      .joined
      .joins(:volunteer_task)
      .where(volunteer_tasks: { status: 'open' })
      .order(updated_at: :desc)
      .limit(5)
      .pluck('volunteer_tasks.title', :volunteer_task_id)
  end

  def skill_entries(user)
    Certification
      .where(user_id: user.id)
      .joins(training_session: :training)
      .limit(5)
      .pluck('trainings.name_en', 'training_sessions.level')
  end

  # [training name, "completed/total"] per training the user has a track in.
  def track_progress_entries(user)
    total_tracks = cached_total_tracks
    user
      .learning_module_tracks
      .includes(learning_module: :training)
      .group_by { |x| x.learning_module.training.name_en }
      .transform_values { |x| x.map(&:status).tally }
      .map { |key, value| [key, track_progress(value, total_tracks[key])] }
  end

  def track_progress(status_counts, total)
    "#{status_counts['Completed'] || 0}/#{total || 0}"
  end

  # Cached total tracks count
  def cached_total_tracks
    Rails.cache.fetch('LearningModuleTotalTracks', expires_in: 1.hour) do
      LearningModule.unscope(:order).joins(:training).group('trainings.name_en').count
    end
  end

  # Cached Recent Repositories
  def cached_recent_projects
    Rails.cache.fetch('StaticPagesRecentRepos', expires_in: 10.minutes) do
      Repository
        .public_repos
        .with_card_data
        .order(created_at: :desc)
        .limit(15)
        .to_a
    end
  end

  # Cached Contact Info
  def cached_contact_info
    Rails.cache.fetch('StaticPagesContactInfo', expires_in: 30.minutes) do
      ContactInfo.where(show_hours: true).order(name: :asc).to_a
    end
  end

  # Cached Workshops (SimpliEvents)
  def cached_workshops
    Rails.cache.fetch('SimpliEventsRecentEvents', expires_in: 15.minutes, race_condition_ttl: 15.seconds) do
      fetch_simpli_events
    end
  end

  # Cached MakerStore Links
  def cached_makerstore_links
    Rails.cache.fetch('ShopifyMakerstoreLinks', expires_in: 1.hour, race_condition_ttl: 15.seconds) do
      home_makerstore_links
    end
  end

  # [space name or nil, "Monday 10:00 - 13:00"] per shadowing shift; a shift
  # without a space has no name, and a stored shift missing a time is left out.
  def shadowing_shift_entries(user)
    user.shadowing_hours.complete.includes(:space).map do |hours|
      end_time = hours.end_time.strftime('%H:%M')
      formatted_time = "#{I18n.l hours.start_time, format: '%A %H:%M'} - #{end_time}"
      [hours.space&.name, formatted_time]
    end
  end

  # The same answer whether or not the address belongs to an account, and when throttled.
  def reset_password_response
    flash.now[:notice] = RESET_PASSWORD_NOTICE
    render :forgot_password
  end

  MAKERSTORE_SHOP = 'uottawa-makerspace.myshopify.com'

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
    # Always the makerspace's own store, with only the access token (as before ShopifyContext
    # existed): no dependency on credentials shop_name/api_key/api_version. ensure_setup! only
    # primes Context.api_version for the client; it never raises and its result is ignored,
    # so an incomplete config behaves as it always did (boot priming, or the client's default).
    access_token = (Rails.application.credentials[Rails.env.to_sym] || {}).dig(:shopify, :password)
    return [] if access_token.blank?

    # to_s: sorbet type-checks access_token as String, and a YAML token of only digits parses as an Integer.
    access_token = access_token.to_s

    ShopifyContext.ensure_setup!
    sess = ShopifyAPI::Auth::Session.new(shop: MAKERSTORE_SHOP, access_token: access_token)
    client = ShopifyConcern::DraftOrders.client(session: sess)

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
    # Class only: a sorbet TypeError (or an HTTP error) message can echo the access token.
    Rails.logger.error("Failed to fetch Shopify collections: #{e.class}")
    []
  end
end
