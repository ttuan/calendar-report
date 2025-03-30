require 'active_support/core_ext/numeric/time'
require 'google/apis/calendar_v3'
require 'googleauth'

class CalendarAnalyzer
  WORKING_HOURS_PER_DAY = 8 # Default working hours per day

  def initialize(start_date, end_date, selected_calendars, credentials)
    @start_date = start_date
    @end_date = end_date
    @selected_calendars = selected_calendars
    @credentials = credentials
    @service = Google::Apis::CalendarV3::CalendarService.new
    @service.authorization = create_credentials
  end

  def analyze_events
    events_by_calendar = {}

    @selected_calendars.each do |calendar_id|
      begin
        puts "Fetching events for calendar: #{calendar_id}"
        puts "Date range: #{@start_date.iso8601} to #{@end_date.iso8601}"

        events = list_events(calendar_id)
        events_by_calendar[calendar_id] = process_events(events)
      rescue Google::Apis::ClientError => e
        puts "Error details: #{e.message}"
        puts "Error body: #{e.body}" if e.body
        puts "Error status: #{e.status_code}"

        if e.message.include?('invalid_grant') || e.message.include?('invalid_token')
          puts "Token expired, refreshing..."
          @service.authorization = refresh_credentials
          events = list_events(calendar_id)
          events_by_calendar[calendar_id] = process_events(events)
        else
          raise e
        end
      end
    end

    events_by_calendar
  end

  private

  def process_events(events)
    events.map do |event|
      start_time = event.start.date_time || event.start.date
      end_time = event.end.date_time || event.end.date

      {
        title: event.summary || "(No title)",
        start: start_time,
        end: end_time,
        duration: calculate_duration(start_time, end_time)
      }
    end
  end

  def create_credentials
    Google::Auth::UserRefreshCredentials.new(
      client_id: ENV['GOOGLE_CLIENT_ID'],
      client_secret: ENV['GOOGLE_CLIENT_SECRET'],
      scope: Google::Apis::CalendarV3::AUTH_CALENDAR_READONLY,
      redirect_uri: 'http://localhost:4567/auth/google_oauth2/callback',
      access_token: @credentials[:access_token],
      refresh_token: @credentials[:refresh_token]
    )
  end

  def refresh_credentials
    credentials = create_credentials
    credentials.fetch_access_token!

    # Update session credentials with new access token
    @credentials[:access_token] = credentials.access_token
    @credentials[:expires_at] = credentials.expires_at

    credentials
  end

  def list_events(calendar_id)
    begin
      # Ensure dates are in the correct format and timezone
      time_min = @start_date.in_time_zone.beginning_of_day.iso8601
      time_max = @end_date.in_time_zone.end_of_day.iso8601

      puts "Fetching events with time range: #{time_min} to #{time_max}"

      all_events = []
      page_token = nil
      
      loop do
        response = @service.list_events(
          calendar_id,
          time_min: time_min,
          time_max: time_max,
          single_events: true,
          order_by: 'startTime',
          max_results: 2500,
          page_token: page_token
        )
        
        all_events.concat(response.items)
        
        # Get the next page token
        page_token = response.next_page_token
        
        # Break the loop if there are no more pages
        break unless page_token
        
        puts "Fetching next page of events for #{calendar_id}, found #{all_events.length} events so far..."
      end
      
      puts "Total #{all_events.length} events found for calendar #{calendar_id}"
      all_events
    rescue Google::Apis::ClientError => e
      puts "Error in list_events:"
      puts "Calendar ID: #{calendar_id}"
      puts "Start date: #{time_min}"
      puts "End date: #{time_max}"
      puts "Error message: #{e.message}"
      puts "Error body: #{e.body}" if e.body
      raise e
    end
  end

  def calculate_duration(start_time, end_time)
    # Only calculate duration for events with specific times (not all-day events)
    if start_time.is_a?(Time) || start_time.is_a?(DateTime)
      # Convert to Time objects and calculate seconds difference
      duration_seconds = (end_time.to_time - start_time.to_time).to_i
      puts "Time event: #{start_time} to #{end_time} = #{duration_seconds} seconds"
      duration_seconds
    else
      # For all-day events or any other format, return 0 duration
      puts "All-day event or unknown format - not counting duration: #{start_time.class}"
      0
    end
  end
end
