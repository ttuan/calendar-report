require 'google/apis/calendar_v3'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'fileutils'
require 'pry'

class GoogleCalendarClient
  OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'
  APPLICATION_NAME = 'Calendar Time Analyzer'
  CREDENTIALS_PATH = 'config/credentials.json'
  TOKEN_PATH = 'config/token.yaml'
  SCOPE = Google::Apis::CalendarV3::AUTH_CALENDAR_READONLY

  def initialize
    @service = Google::Apis::CalendarV3::CalendarService.new
    @service.client_options.application_name = APPLICATION_NAME
    @service.authorization = authorize
  end

  def list_calendars
    response = @service.list_calendar_list
    response.items.map { |calendar| { id: calendar.id, name: calendar.summary } }
  end

  def list_events(calendar_id, time_min, time_max)
    response = @service.list_events(
      calendar_id,
      time_min: time_min.iso8601,
      time_max: time_max.iso8601,
      single_events: true,
      order_by: 'startTime'
    )
    response.items
  end

  private

  def authorize
    credentials = Google::Auth::UserRefreshCredentials.new(
      client_id: ENV['GOOGLE_CLIENT_ID'],
      client_secret: ENV['GOOGLE_CLIENT_SECRET'],
      scope: SCOPE
    )

    # If you have a refresh token, you can set it here
    # credentials.refresh_token = ENV['GOOGLE_REFRESH_TOKEN']

    credentials
  end
end
