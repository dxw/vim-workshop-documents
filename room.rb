require "service"

class Room
  attr_reader :name, :css_class, :presence_colour_rgb

  def initialize(name:, css_class:, gcal_identifier:, presence_colour_rgb:)
    @name = name
    @css_class = css_class
    @gcal_identifier = gcal_identifier
    @presence_colour_rgb = presence_colour_rgb
    @events_cache_expires = Time.now
  end

  def empty
    events.select { |event| event[:now] }.empty?
  end

  def upcoming_event_today
    events.select { |event| !(event[:now]) }.any?
  end

  def empty_until_string
    if upcoming_event_today
      events[0][:start_time_string]
    else
      "Tomorrow"
    end
  end

  def minutes_to_next_event
    if events.empty? # No upcoming events at all
      false
    elsif empty # Currently empty, but won't be later
      ((events[0][:start_time] - DateTime.now) * 24 * 60).to_i
    elsif upcoming_event_today # Currently busy, and another event later today
      ((events[1][:start_time] - DateTime.now) * 24 * 60).to_i
    else
      false
    end
  end

  def minutes_to_end_of_event
    if events.empty?
      false
    else
      ((events[0][:end_time] - DateTime.now) * 24 * 60).to_i
    end
  end

  def events
    if @events_cache_expires < Time.now
      @cached_events = fetch_events(@gcal_identifier).map { |event|
        {
          summary: event.summary || "Private or unspecified",
          start_time: event.start.date_time,
          start_time_string: event.start.date || event.start.date_time.strftime("%l:%M %P"),
          end_time: event.end.date_time,
          end_time_string: event.end.date || event.end.date_time.strftime("%l:%M %P"),
          organiser: event.organizer ? (event.organizer.display_name || event.organizer.email) : "Private or unspecified",
          now: DateTime.now.between?(event.start.date_time, event.end.date_time)
        }
      }
      @events_cache_expires = Time.now + CACHE_EXPIRY_TIMEOUT
    end

    @cached_events
  end

  # Fetch the next 5 events today for this room
  def fetch_events(calendar_id)
    response = service.list_events(calendar_id,
      max_results: 5,
      single_events: true,
      order_by: "startTime",
      time_min: Time.now.iso8601,
      time_max: Date.today.+(1).to_time.iso8601)

    # filter out any declined events – they normally represent a clash or room release
    response.items.reject { |event|
      next if event.attendees.nil?
      event.attendees.find(&:self).response_status == "declined"
    }
  end
end
