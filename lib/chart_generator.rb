require 'active_support/core_ext/numeric/time'

class ChartGenerator
  def initialize(events_by_calendar, group_by)
    @events_by_calendar = events_by_calendar
    @group_by = group_by
  end

  def generate_data
    grouped_data = {}

    @events_by_calendar.each do |calendar_id, events|
      grouped_data[calendar_id] = group_events(events)
    end

    format_for_chart(grouped_data)
  end

  private

  def group_events(events)
    case @group_by
    when 'week'
      group_by_week(events)
    when 'month'
      group_by_month(events)
    else
      group_by_day(events)
    end
  end

  def distribute_event_duration(event, result)
    # Skip events with zero duration
    return if event[:duration] == 0

    # Convert to dates for grouping
    start_date = event[:start].respond_to?(:to_date) ? event[:start].to_date : event[:start]
    end_date = event[:end].respond_to?(:to_date) ? event[:end].to_date : event[:end]

    # For single-day events
    if start_date == end_date
      result[start_date] ||= 0
      result[start_date] += event[:duration]
      return
    end

    # For multi-day events, distribute duration across days
    # Since we've eliminated all-day events in the analyzer, we're only dealing
    # with regular events that span multiple days

    # Calculate total duration and distribute proportionally
    days_count = (end_date - start_date).to_i + 1
    daily_duration = event[:duration] / days_count.to_f

    # Distribute evenly across the days
    (start_date..end_date).each do |date|
      result[date] ||= 0
      result[date] += daily_duration.to_i
    end
  end

  def group_by_week(events)
    # First distribute events by day
    daily_result = {}
    events.each do |event|
      distribute_event_duration(event, daily_result)
    end

    # Then aggregate days by week
    result = {}
    daily_result.each do |date, duration|
      week_start = date.beginning_of_week
      result[week_start] ||= 0
      result[week_start] += duration
    end

    result
  end

  def group_by_month(events)
    # First distribute events by day
    daily_result = {}
    events.each do |event|
      distribute_event_duration(event, daily_result)
    end

    # Then aggregate days by month
    result = {}
    daily_result.each do |date, duration|
      month_start = date.beginning_of_month
      result[month_start] ||= 0
      result[month_start] += duration
    end

    result
  end

  def group_by_day(events)
    result = {}
    events.each do |event|
      distribute_event_duration(event, result)
    end
    result
  end

  def format_for_chart(grouped_data)
    all_dates = get_all_dates(grouped_data)

    {
      labels: all_dates.map { |date| format_date(date) },
      datasets: generate_datasets(grouped_data, all_dates)
    }
  end

  def get_all_dates(grouped_data)
    # Get all unique dates from all calendars and sort them
    all_dates = grouped_data.values.flat_map(&:keys).uniq.sort

    # If there are no dates (no events), return empty array
    return [] if all_dates.empty?

    # Fill in any missing dates in the range
    start_date = all_dates.first
    end_date = all_dates.last

    case @group_by
    when 'week'
      (start_date..end_date).step(7).map { |date| date.beginning_of_week }
    when 'month'
      # Generate all months between start and end date
      result = []
      current = start_date.beginning_of_month
      while current <= end_date
        result << current
        current = current.next_month.beginning_of_month
      end
      result
    else
      # Generate all days between start and end date
      (start_date..end_date).to_a
    end
  end

  def generate_datasets(grouped_data, all_dates)
    grouped_data.map do |calendar_id, data|
      {
        label: calendar_id,
        data: all_dates.map { |date| data[date] || 0 },
        borderColor: generate_color(calendar_id),
        fill: false
      }
    end
  end

  def format_date(date)
    case @group_by
    when 'week'
      date.strftime('%Y-%m-%d')
    when 'month'
      date.strftime('%Y-%m')
    else
      date.strftime('%Y-%m-%d')
    end
  end

  def generate_color(calendar_id)
    # Color palette mapping based on calendar names
    color_map = {
      # Map colors based on calendar names/themes from the image
      'Personal Growth' => '#dd7834',  # Sorrell Brown
      'Personal' => '#388592',         # Silver Tree
      'Fun & Recreation' => '#2782a2',  # Calypso
      'Family' => '#cb5252',           # Mojo
      'Work' => '#71b199',             # Goblin
      'Health' => '#957367',           # Flint
      'Romance' => '#c0243a',          # Mojo
      'Friends' => '#cc5e5e',          # Abbey
      'Birthdays' => '#284128',        # Green Kelp
      'Tasks' => '#474544',            # Masala
      'tran.van.tuan' => '#c53130'
    }

    # Default background color if no match found
    default_color = '#1c1c1c'          # Cod Gray

    # Find the best match for calendar name in our color map
    color_match = color_map.keys.find { |key| calendar_id.include?(key) }

    if color_match
      return color_map[color_match]
    else
      # Fallback to hash-based color generation but using our palette
      colors = color_map.values
      return colors[calendar_id.hash.abs % colors.length]
    end
  end
end
