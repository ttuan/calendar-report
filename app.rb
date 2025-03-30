require 'sinatra'
require 'chartkick'
require 'json'
require 'google/apis/calendar_v3'
require 'googleauth'
require 'dotenv/load'
require 'active_support'
require 'active_support/core_ext'
require 'active_support/time'
require_relative 'lib/calendar_analyzer'
require_relative 'lib/chart_generator'
require 'pry'

# Configure ActiveSupport
Time.zone = 'Asia/Ho_Chi_Minh'

class CalendarApp < Sinatra::Base
  enable :sessions
  set :public_folder, 'public'
  set :views, 'views'

  # Load environment variables
  Dotenv.load

  # OAuth configuration
  GOOGLE_CLIENT_ID = ENV['GOOGLE_CLIENT_ID']
  GOOGLE_CLIENT_SECRET = ENV['GOOGLE_CLIENT_SECRET']
  REDIRECT_URI = 'http://localhost:4567/auth/google_oauth2/callback'
  SCOPE = Google::Apis::CalendarV3::AUTH_CALENDAR_READONLY

  # Parse JSON request body
  before do
    if request.content_type && request.content_type.include?('application/json')
      begin
        request.body.rewind
        @request_payload = JSON.parse(request.body.read, symbolize_names: true)
      rescue JSON::ParserError => e
        puts "Error parsing JSON: #{e.message}"
        @request_payload = {}
      end
    end
  end

  before do
    # Skip authentication check for these paths
    return if ['/', '/auth/google_oauth2', '/auth/google_oauth2/callback'].include?(request.path_info)

    # Require authentication for all other paths
    unless authenticated?
      redirect '/'
    end

    # Check if token needs refresh
    refresh_token_if_needed
  end

  get '/' do
    if authenticated?
      @calendars = list_calendars
      erb :'index.html'
    else
      erb :'login.html'
    end
  end

  get '/auth/google_oauth2' do
    credentials = Google::Auth::UserRefreshCredentials.new(
      client_id: GOOGLE_CLIENT_ID,
      client_secret: GOOGLE_CLIENT_SECRET,
      scope: SCOPE,
      redirect_uri: REDIRECT_URI
    )

    redirect credentials.authorization_uri(
      access_type: 'offline',
      include_granted_scopes: true
    )
  end

  get '/auth/google_oauth2/callback' do
    credentials = Google::Auth::UserRefreshCredentials.new(
      client_id: GOOGLE_CLIENT_ID,
      client_secret: GOOGLE_CLIENT_SECRET,
      scope: SCOPE,
      redirect_uri: REDIRECT_URI
    )

    credentials.code = params[:code]
    credentials.fetch_access_token!

    session[:credentials] = {
      access_token: credentials.access_token,
      refresh_token: credentials.refresh_token,
      expires_at: credentials.expires_at
    }

    redirect '/'
  end

  get '/logout' do
    session.clear
    redirect '/'
  end

  post '/analyze' do
    # Parse JSON payload or use form params
    payload = @request_payload || params

    puts "Received parameters: #{payload.inspect}"

    start_date = Date.parse(payload[:start_date] || params[:start_date])
    end_date = Date.parse(payload[:end_date] || params[:end_date])
    selected_calendars = payload[:calendars] || params[:calendars] || []
    group_by = payload[:group_by] || params[:group_by] || 'week'

    # Validate dates
    today = Date.today
    if end_date > today
      end_date = today
    end

    if start_date > end_date
      status 400
      return { error: 'Start date must be before end date' }.to_json
    end

    puts "Analyzing calendars:"
    puts "Start date: #{start_date}"
    puts "End date: #{end_date}"
    puts "Selected calendars: #{selected_calendars.inspect}"
    puts "Group by: #{group_by}"
    puts "Session credentials: #{session[:credentials].inspect}"

    if selected_calendars.empty?
      status 400
      return { error: 'Please select at least one calendar' }.to_json
    end

    begin
      # Get calendar display names for later use
      all_calendars = list_calendars
      calendar_names = all_calendars.each_with_object({}) do |cal, hash|
        hash[cal[:id]] = cal[:display_name] || cal[:name]
      end

      analyzer = CalendarAnalyzer.new(start_date, end_date, selected_calendars, session[:credentials])
      events = analyzer.analyze_events

      # Replace the calendar IDs with display names
      events_with_names = {}
      events.each do |calendar_id, calendar_events|
        display_name = calendar_names[calendar_id] || calendar_id
        events_with_names[display_name] = calendar_events
      end

      chart_data = ChartGenerator.new(events_with_names, group_by).generate_data

      # Add raw event data for debugging
      if ENV['DEBUG_MODE'] == 'true'
        chart_data[:raw_events] = events_with_names
      end

      # Ensure we have the right data structure for Chart.js
      puts "Generated chart data: #{chart_data.inspect}"

      content_type :json
      chart_data.to_json
    rescue StandardError => e
      puts "Error in /analyze:"
      puts e.message
      puts e.backtrace
      status 500
      { error: e.message }.to_json
    end
  end

  private

  def authenticated?
    session[:credentials] && session[:credentials][:access_token]
  end

  def refresh_token_if_needed
    return unless authenticated?

    credentials = Google::Auth::UserRefreshCredentials.new(
      client_id: GOOGLE_CLIENT_ID,
      client_secret: GOOGLE_CLIENT_SECRET,
      scope: SCOPE,
      redirect_uri: REDIRECT_URI,
      access_token: session[:credentials][:access_token],
      refresh_token: session[:credentials][:refresh_token]
    )

    # Refresh token if it's expired or about to expire (within 5 minutes)
    if credentials.expired? || (credentials.expires_at && credentials.expires_at < Time.now + 300)
      puts "Refreshing token..."
      credentials.fetch_access_token!
      session[:credentials][:access_token] = credentials.access_token
      session[:credentials][:expires_at] = credentials.expires_at
      puts "Token refreshed successfully"
    end
  end

  def list_calendars
    credentials = Google::Auth::UserRefreshCredentials.new(
      client_id: GOOGLE_CLIENT_ID,
      client_secret: GOOGLE_CLIENT_SECRET,
      scope: SCOPE,
      redirect_uri: REDIRECT_URI,
      access_token: session[:credentials][:access_token],
      refresh_token: session[:credentials][:refresh_token]
    )

    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = credentials

    puts "Fetching calendar list..."
    response = service.list_calendar_lists
    calendars = response.items.map do |calendar|
      {
        id: calendar.id,
        name: calendar.summary,
        display_name: format_calendar_name(calendar.id, calendar.summary)
      }
    end
    puts "Available calendars: #{calendars.inspect}"
    calendars
  end

  def format_calendar_name(calendar_id, summary)
    # Use the summary if it exists
    return summary if summary && !summary.empty?

    # Otherwise try to make a nice name from the ID
    if calendar_id.include?('@')
      parts = calendar_id.split('@')
      if parts[1] == 'group.calendar.google.com'
        return "Calendar #{calendar_id.first(6)}"
      end
      return parts[0] # Return the username part of the email
    end

    # Fallback
    calendar_id
  end
end

# Run the application
if __FILE__ == $0
  CalendarApp.run!
end
