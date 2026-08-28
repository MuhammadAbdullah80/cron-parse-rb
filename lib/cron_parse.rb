# frozen_string_literal: true

require "date"

# Parses a five-field cron expression and answers two questions about it:
# whether a given time matches, and when it next fires.
#
#   schedule = CronParse.parse("*/15 9-17 * * MON-FRI")
#   schedule.matches?(Time.utc(2026, 3, 4, 9, 15))   # => true
#   schedule.next_after(Time.utc(2026, 3, 4, 9, 20)) # => 2026-03-04 09:30 UTC
#
# No dependencies outside the standard library.
module CronParse
  class ParseError < ArgumentError; end

  MONTH_NAMES = %w[jan feb mar apr may jun jul aug sep oct nov dec].freeze

  WEEKDAY_NAMES = %w[sun mon tue wed thu fri sat].freeze

  # @yearly and friends, as understood by every cron implementation.
  SHORTCUTS = {
    "@yearly"   => "0 0 1 1 *",
    "@annually" => "0 0 1 1 *",
    "@monthly"  => "0 0 1 * *",
    "@weekly"   => "0 0 * * 0",
    "@daily"    => "0 0 * * *",
    "@midnight" => "0 0 * * *",
    "@hourly"   => "0 * * * *"
  }.freeze

  # How far next_after will look before giving up. Four years covers the worst
  # legitimate case - "0 0 29 2 *" fires only on a leap day - and the fifth is
  # slack, so an expression that can never fire returns nil instead of looping.
  SEARCH_YEARS = 5

  Field = Struct.new(:key, :label, :range, :names, keyword_init: true)

  FIELDS = [
    Field.new(key: :minute,       label: "minute",       range: 0..59, names: nil),
    Field.new(key: :hour,         label: "hour",         range: 0..23, names: nil),
    Field.new(key: :day_of_month, label: "day of month", range: 1..31, names: nil),
    Field.new(key: :month,        label: "month",        range: 1..12, names: MONTH_NAMES),
    # 0 and 7 both mean Sunday, which is why this range is 0..7 and not 0..6.
    Field.new(key: :day_of_week,  label: "day of week",  range: 0..7,  names: WEEKDAY_NAMES)
  ].freeze

  def self.parse(expression)
    Schedule.parse(expression)
  end

  class Schedule
    attr_reader :expression, :minutes, :hours, :days_of_month, :months, :days_of_week

    def self.parse(expression)
      raise ParseError, "expected a String, got #{expression.class}" unless expression.is_a?(String)

      text = expression.strip
      raise ParseError, "expression is empty" if text.empty?

      if text.start_with?("@")
        expanded = SHORTCUTS[text.downcase]
        unless expanded
          raise ParseError,
                "unknown shortcut #{text.inspect}; known: #{SHORTCUTS.keys.sort.join(', ')}"
        end
        text = expanded
      end

      parts = text.split(/\s+/)
      unless parts.length == 5
        raise ParseError,
              "expected 5 fields (minute hour day-of-month month day-of-week), got #{parts.length}"
      end

      parsed = {}
      restricted = {}
      FIELDS.each_with_index do |field, i|
        values, is_restricted = parse_field(parts[i], field)
        parsed[field.key] = values
        restricted[field.key] = is_restricted
      end

      new(expression: expression, values: parsed, restricted: restricted)
    end

    # Returns [SortedSet-of-Integer, restricted?]. "restricted?" is false only
    # when the field was a bare "*", which day_matches? needs in order to apply
    # cron's day-of-month/day-of-week rule.
    def self.parse_field(text, field)
      return [field.range.to_a, false] if text == "*"

      values = []
      text.split(",", -1).each do |part|
        if part.empty?
          raise ParseError, "#{field.label}: empty element in #{text.inspect}"
        end
        values.concat(parse_element(part, field, text))
      end

      values = values.map { |v| v == 7 && field.key == :day_of_week ? 0 : v }
      [values.uniq.sort, true]
    end

    def self.parse_element(part, field, whole)
      body, step_text = part.split("/", -1)
      if part.count("/") > 1
        raise ParseError, "#{field.label}: more than one step in #{part.inspect}"
      end

      step = 1
      unless step_text.nil?
        if step_text.empty?
          raise ParseError, "#{field.label}: missing step value in #{part.inspect}"
        end
        unless step_text.match?(/\A\d+\z/)
          raise ParseError, "#{field.label}: step must be a positive integer, got #{step_text.inspect}"
        end
        step = step_text.to_i
        raise ParseError, "#{field.label}: step must be at least 1 in #{part.inspect}" if step.zero?
      end

      from, to =
        if body == "*"
          [field.range.first, field.range.last]
        elsif body.include?("-")
          lo, hi, extra = body.split("-", -1)
          unless extra.nil?
            raise ParseError, "#{field.label}: malformed range #{body.inspect}"
          end
          [resolve(lo, field, whole), resolve(hi, field, whole)]
        else
          single = resolve(body, field, whole)
          # A bare value with a step means "from here to the end of the range",
          # matching Vixie cron: "5/10" in the minute field is 5,15,25,35,45,55.
          step_text.nil? ? [single, single] : [single, field.range.last]
        end

      if from > to
        raise ParseError,
              "#{field.label}: range #{body.inspect} runs backwards " \
              "(#{from} to #{to}); wrapping ranges are not supported"
      end

      from.step(to, step).to_a
    end

    def self.resolve(token, field, whole)
      if token.nil? || token.empty?
        raise ParseError, "#{field.label}: empty value in #{whole.inspect}"
      end

      value =
        if token.match?(/\A\d+\z/)
          token.to_i
        elsif field.names
          index = field.names.index(token.downcase)
          if index.nil?
            raise ParseError,
                  "#{field.label}: #{token.inspect} is not a number or a name " \
                  "(#{field.names.map(&:upcase).join(', ')})"
          end
          # Month names are 1-based, weekday names 0-based.
          field.key == :month ? index + 1 : index
        else
          raise ParseError, "#{field.label}: #{token.inspect} is not a number"
        end

      unless field.range.cover?(value)
        raise ParseError,
              "#{field.label}: #{value} is out of range " \
              "(#{field.range.first}-#{field.range.last})"
      end
      value
    end

    private_class_method :parse_field, :parse_element, :resolve

    def initialize(expression:, values:, restricted:)
      @expression = expression
      @minutes = values[:minute].freeze
      @hours = values[:hour].freeze
      @days_of_month = values[:day_of_month].freeze
      @months = values[:month].freeze
      @days_of_week = values[:day_of_week].freeze
      @dom_restricted = restricted[:day_of_month]
      @dow_restricted = restricted[:day_of_week]
      freeze
    end

    def matches?(time)
      t = coerce(time)
      @minutes.include?(t.min) &&
        @hours.include?(t.hour) &&
        @months.include?(t.month) &&
        day_matches?(t)
    end

    # The first matching time strictly after `from`, or nil if the expression
    # cannot fire within SEARCH_YEARS.
    def next_after(from)
      t = truncate_to_minute(coerce(from)) + 60
      final_year = t.year + SEARCH_YEARS

      while t.year <= final_year
        unless @months.include?(t.month)
          t = start_of_next_month(t)
          next
        end
        unless day_matches?(t)
          t = start_of_next_day(t)
          next
        end
        unless @hours.include?(t.hour)
          t = start_of_next_hour(t)
          next
        end
        unless @minutes.include?(t.min)
          t += 60
          next
        end
        return t
      end

      nil
    end

    # The next `count` firing times after `from`.
    def next_occurrences(from, count)
      raise ArgumentError, "count must be positive" unless count.is_a?(Integer) && count.positive?

      out = []
      cursor = from
      count.times do
        cursor = next_after(cursor)
        break if cursor.nil?
        out << cursor
      end
      out
    end

    def to_s
      @expression
    end

    def inspect
      "#<CronParse::Schedule #{@expression.inspect}>"
    end

    private

    # Cron's oddest rule: when *both* day-of-month and day-of-week are
    # restricted, a day matches if *either* does - so "0 0 1 * MON" fires on the
    # 1st and on every Monday, not only on Mondays that fall on the 1st. When
    # only one is restricted it alone decides.
    def day_matches?(time)
      dom = @days_of_month.include?(time.day)
      dow = @days_of_week.include?(time.wday)

      if @dom_restricted && @dow_restricted
        dom || dow
      elsif @dom_restricted
        dom
      elsif @dow_restricted
        dow
      else
        true
      end
    end

    def coerce(time)
      unless time.respond_to?(:year) && time.respond_to?(:min)
        raise ArgumentError, "expected a Time, got #{time.class}"
      end
      time
    end

    # Day and month steps go through Date rather than adding 86_400 seconds, so
    # a daylight-saving transition cannot shift the result by an hour.
    def build(like, year, month, day, hour, minute)
      if like.utc?
        Time.utc(year, month, day, hour, minute, 0)
      else
        Time.local(year, month, day, hour, minute, 0)
      end
    end

    def truncate_to_minute(t)
      build(t, t.year, t.month, t.day, t.hour, t.min)
    end

    def start_of_next_hour(t)
      return start_of_next_day(t) if t.hour == 23
      build(t, t.year, t.month, t.day, t.hour + 1, 0)
    end

    def start_of_next_day(t)
      d = Date.new(t.year, t.month, t.day) + 1
      build(t, d.year, d.month, d.day, 0, 0)
    end

    def start_of_next_month(t)
      d = Date.new(t.year, t.month, 1) >> 1
      build(t, d.year, d.month, 1, 0, 0)
    end
  end
end
