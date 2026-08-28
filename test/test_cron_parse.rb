# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/cron_parse"

class TestParsing < Minitest::Test
  def test_every_minute
    s = CronParse.parse("* * * * *")
    assert_equal (0..59).to_a, s.minutes
    assert_equal (0..23).to_a, s.hours
    assert_equal (1..31).to_a, s.days_of_month
    assert_equal (1..12).to_a, s.months
  end

  def test_single_values
    s = CronParse.parse("5 4 3 2 1")
    assert_equal [5], s.minutes
    assert_equal [4], s.hours
    assert_equal [3], s.days_of_month
    assert_equal [2], s.months
    assert_equal [1], s.days_of_week
  end

  def test_lists
    assert_equal [0, 15, 30, 45], CronParse.parse("0,15,30,45 * * * *").minutes
  end

  def test_list_is_sorted_and_deduplicated
    assert_equal [5, 10, 20], CronParse.parse("20,5,10,5 * * * *").minutes
  end

  def test_ranges
    assert_equal (9..17).to_a, CronParse.parse("* 9-17 * * *").hours
  end

  def test_step_over_wildcard
    assert_equal [0, 15, 30, 45], CronParse.parse("*/15 * * * *").minutes
  end

  def test_step_over_range
    assert_equal [1, 4, 7, 10], CronParse.parse("* * * 1-10/3 * ").months.first(4)
  end

  def test_step_from_a_bare_value_runs_to_the_end_of_the_range
    # Vixie cron reads "5/10" as "from 5, every 10, to the end of the field".
    assert_equal [5, 15, 25, 35, 45, 55], CronParse.parse("5/10 * * * *").minutes
  end

  def test_combined_list_of_ranges_and_steps
    assert_equal [0, 1, 2, 30, 45], CronParse.parse("0-2,30,45 * * * *").minutes
  end

  def test_month_names
    assert_equal [1], CronParse.parse("0 0 1 JAN *").months
    assert_equal [12], CronParse.parse("0 0 1 dec *").months
  end

  def test_month_name_range
    assert_equal (6..8).to_a, CronParse.parse("0 0 1 JUN-AUG *").months
  end

  def test_weekday_names
    assert_equal [1], CronParse.parse("0 0 * * MON").days_of_week
    assert_equal [0], CronParse.parse("0 0 * * sun").days_of_week
  end

  def test_weekday_name_range
    assert_equal [1, 2, 3, 4, 5], CronParse.parse("0 0 * * MON-FRI").days_of_week
  end

  def test_seven_is_sunday
    # Both 0 and 7 mean Sunday, and they collapse to one value.
    assert_equal [0], CronParse.parse("0 0 * * 7").days_of_week
    assert_equal [0], CronParse.parse("0 0 * * 0,7").days_of_week
  end

  def test_surrounding_whitespace_is_tolerated
    assert_equal [5], CronParse.parse("   5 * * * *   ").minutes
  end

  def test_multiple_spaces_between_fields
    assert_equal [5], CronParse.parse("5    *  *   *    *").minutes
  end

  def test_to_s_returns_the_original_expression
    assert_equal "*/15 * * * *", CronParse.parse("*/15 * * * *").to_s
  end
end

class TestShortcuts < Minitest::Test
  def test_daily
    s = CronParse.parse("@daily")
    assert_equal [0], s.minutes
    assert_equal [0], s.hours
  end

  def test_midnight_is_daily
    assert_equal CronParse.parse("@daily").minutes, CronParse.parse("@midnight").minutes
  end

  def test_hourly
    s = CronParse.parse("@hourly")
    assert_equal [0], s.minutes
    assert_equal (0..23).to_a, s.hours
  end

  def test_weekly_is_sunday
    assert_equal [0], CronParse.parse("@weekly").days_of_week
  end

  def test_monthly_is_the_first
    assert_equal [1], CronParse.parse("@monthly").days_of_month
  end

  def test_yearly_is_january_first
    s = CronParse.parse("@yearly")
    assert_equal [1], s.days_of_month
    assert_equal [1], s.months
  end

  def test_annually_matches_yearly
    assert_equal CronParse.parse("@yearly").months, CronParse.parse("@annually").months
  end

  def test_shortcuts_are_case_insensitive
    assert_equal [0], CronParse.parse("@DAILY").hours
  end

  def test_unknown_shortcut_is_rejected
    err = assert_raises(CronParse::ParseError) { CronParse.parse("@fortnightly") }
    assert_match(/unknown shortcut/, err.message)
  end
end

class TestValidation < Minitest::Test
  def assert_parse_error(expression, pattern)
    err = assert_raises(CronParse::ParseError) { CronParse.parse(expression) }
    assert_match(pattern, err.message)
  end

  def test_too_few_fields
    assert_parse_error("* * * *", /expected 5 fields/)
  end

  def test_too_many_fields
    assert_parse_error("* * * * * *", /expected 5 fields/)
  end

  def test_empty_expression
    assert_parse_error("", /empty/)
  end

  def test_non_string
    assert_raises(CronParse::ParseError) { CronParse.parse(42) }
  end

  def test_minute_out_of_range
    assert_parse_error("60 * * * *", /minute: 60 is out of range/)
  end

  def test_hour_out_of_range
    assert_parse_error("* 24 * * *", /hour: 24 is out of range/)
  end

  def test_day_of_month_zero_is_out_of_range
    assert_parse_error("* * 0 * *", /day of month: 0 is out of range/)
  end

  def test_month_out_of_range
    assert_parse_error("* * * 13 *", /month: 13 is out of range/)
  end

  def test_day_of_week_out_of_range
    assert_parse_error("* * * * 8", /day of week: 8 is out of range/)
  end

  def test_unknown_name
    assert_parse_error("* * * SMARCH *", /not a number or a name/)
  end

  def test_name_in_a_numeric_only_field
    assert_parse_error("MON * * * *", /is not a number/)
  end

  def test_backwards_range
    assert_parse_error("* 17-9 * * *", /runs backwards/)
  end

  def test_zero_step
    assert_parse_error("*/0 * * * *", /at least 1/)
  end

  def test_missing_step
    assert_parse_error("*/ * * * *", /missing step/)
  end

  def test_non_numeric_step
    assert_parse_error("*/abc * * * *", /step must be a positive integer/)
  end

  def test_double_step
    assert_parse_error("*/2/3 * * * *", /more than one step/)
  end

  def test_empty_list_element
    assert_parse_error("1,,2 * * * *", /empty element/)
  end

  def test_malformed_range
    assert_parse_error("1-2-3 * * * *", /malformed range/)
  end
end

class TestMatches < Minitest::Test
  def test_every_minute_matches_anything
    s = CronParse.parse("* * * * *")
    assert s.matches?(Time.utc(2026, 3, 4, 13, 37))
  end

  def test_exact_minute
    s = CronParse.parse("30 9 * * *")
    assert s.matches?(Time.utc(2026, 3, 4, 9, 30))
    refute s.matches?(Time.utc(2026, 3, 4, 9, 31))
    refute s.matches?(Time.utc(2026, 3, 4, 10, 30))
  end

  def test_step_matches_only_on_the_step
    s = CronParse.parse("*/15 * * * *")
    assert s.matches?(Time.utc(2026, 3, 4, 9, 0))
    assert s.matches?(Time.utc(2026, 3, 4, 9, 15))
    refute s.matches?(Time.utc(2026, 3, 4, 9, 16))
  end

  def test_weekday_range
    s = CronParse.parse("0 9 * * MON-FRI")
    assert s.matches?(Time.utc(2026, 3, 4, 9, 0)),  "2026-03-04 is a Wednesday"
    refute s.matches?(Time.utc(2026, 3, 7, 9, 0)),  "2026-03-07 is a Saturday"
    refute s.matches?(Time.utc(2026, 3, 8, 9, 0)),  "2026-03-08 is a Sunday"
  end

  def test_seconds_are_ignored
    s = CronParse.parse("30 9 * * *")
    assert s.matches?(Time.utc(2026, 3, 4, 9, 30, 59))
  end

  def test_non_time_is_rejected
    assert_raises(ArgumentError) { CronParse.parse("* * * * *").matches?("noon") }
  end
end

class TestDayOfMonthAndWeekAreOred < Minitest::Test
  # Cron's oddest rule: with both day fields restricted, either one matching is
  # enough. Every other pair of fields is ANDed.
  def setup
    @s = CronParse.parse("0 0 1 * MON")
  end

  def test_matches_on_the_first_whatever_the_weekday
    # 2026-04-01 is a Wednesday.
    assert @s.matches?(Time.utc(2026, 4, 1, 0, 0))
  end

  def test_matches_on_a_monday_that_is_not_the_first
    # 2026-04-06 is a Monday.
    assert @s.matches?(Time.utc(2026, 4, 6, 0, 0))
  end

  def test_does_not_match_a_day_that_is_neither
    # 2026-04-08 is a Wednesday.
    refute @s.matches?(Time.utc(2026, 4, 8, 0, 0))
  end

  def test_only_day_of_month_restricted_is_anded_as_usual
    s = CronParse.parse("0 0 1 * *")
    assert s.matches?(Time.utc(2026, 4, 1, 0, 0))
    refute s.matches?(Time.utc(2026, 4, 6, 0, 0))
  end

  def test_only_day_of_week_restricted_is_anded_as_usual
    s = CronParse.parse("0 0 * * MON")
    refute s.matches?(Time.utc(2026, 4, 1, 0, 0))
    assert s.matches?(Time.utc(2026, 4, 6, 0, 0))
  end
end

class TestNextAfter < Minitest::Test
  def test_next_minute
    s = CronParse.parse("* * * * *")
    assert_equal Time.utc(2026, 3, 4, 9, 1), s.next_after(Time.utc(2026, 3, 4, 9, 0))
  end

  def test_strictly_after
    # A time that already matches is not its own next occurrence.
    s = CronParse.parse("0 9 * * *")
    assert_equal Time.utc(2026, 3, 5, 9, 0), s.next_after(Time.utc(2026, 3, 4, 9, 0))
  end

  def test_seconds_are_truncated_not_rounded
    s = CronParse.parse("* * * * *")
    assert_equal Time.utc(2026, 3, 4, 9, 1), s.next_after(Time.utc(2026, 3, 4, 9, 0, 30))
  end

  def test_within_the_hour
    s = CronParse.parse("*/15 * * * *")
    assert_equal Time.utc(2026, 3, 4, 9, 30), s.next_after(Time.utc(2026, 3, 4, 9, 20))
  end

  def test_rolls_into_the_next_hour
    s = CronParse.parse("5 * * * *")
    assert_equal Time.utc(2026, 3, 4, 10, 5), s.next_after(Time.utc(2026, 3, 4, 9, 30))
  end

  def test_rolls_into_the_next_day
    s = CronParse.parse("0 9 * * *")
    assert_equal Time.utc(2026, 3, 5, 9, 0), s.next_after(Time.utc(2026, 3, 4, 10, 0))
  end

  def test_rolls_into_the_next_month
    s = CronParse.parse("0 0 1 * *")
    assert_equal Time.utc(2026, 4, 1, 0, 0), s.next_after(Time.utc(2026, 3, 15, 12, 0))
  end

  def test_rolls_into_the_next_year
    s = CronParse.parse("0 0 1 1 *")
    assert_equal Time.utc(2027, 1, 1, 0, 0), s.next_after(Time.utc(2026, 6, 1, 0, 0))
  end

  def test_skips_a_month_that_is_too_short
    # The 31st does not exist in April, so this jumps to May.
    s = CronParse.parse("0 0 31 * *")
    assert_equal Time.utc(2026, 5, 31, 0, 0), s.next_after(Time.utc(2026, 4, 1, 0, 0))
  end

  def test_finds_the_next_leap_day
    s = CronParse.parse("0 0 29 2 *")
    assert_equal Time.utc(2028, 2, 29, 0, 0), s.next_after(Time.utc(2026, 3, 1, 0, 0))
  end

  def test_weekday_schedule_skips_the_weekend
    s = CronParse.parse("0 9 * * MON-FRI")
    # 2026-03-06 is a Friday; the next weekday is Monday the 9th.
    assert_equal Time.utc(2026, 3, 9, 9, 0), s.next_after(Time.utc(2026, 3, 6, 9, 0))
  end

  def test_impossible_expression_returns_nil
    # There is no 30th of February.
    assert_nil CronParse.parse("0 0 30 2 *").next_after(Time.utc(2026, 1, 1, 0, 0))
  end

  def test_result_keeps_the_utc_flag
    assert CronParse.parse("* * * * *").next_after(Time.utc(2026, 3, 4, 9, 0)).utc?
  end

  def test_non_time_is_rejected
    assert_raises(ArgumentError) { CronParse.parse("* * * * *").next_after("noon") }
  end
end

class TestNextOccurrences < Minitest::Test
  def test_returns_the_requested_count
    s = CronParse.parse("0 */6 * * *")
    got = s.next_occurrences(Time.utc(2026, 3, 4, 0, 0), 4)
    assert_equal [
      Time.utc(2026, 3, 4, 6, 0),
      Time.utc(2026, 3, 4, 12, 0),
      Time.utc(2026, 3, 4, 18, 0),
      Time.utc(2026, 3, 5, 0, 0)
    ], got
  end

  def test_every_occurrence_matches
    s = CronParse.parse("*/7 9-11 * * *")
    s.next_occurrences(Time.utc(2026, 3, 4, 0, 0), 10).each do |t|
      assert s.matches?(t), "#{t} should match #{s}"
    end
  end

  def test_occurrences_are_strictly_increasing
    s = CronParse.parse("*/13 * * * *")
    got = s.next_occurrences(Time.utc(2026, 3, 4, 0, 0), 20)
    assert_equal got.sort, got
    assert_equal got.uniq, got
  end

  def test_stops_early_when_the_schedule_runs_out
    assert_empty CronParse.parse("0 0 30 2 *").next_occurrences(Time.utc(2026, 1, 1), 3)
  end

  def test_count_must_be_positive
    s = CronParse.parse("* * * * *")
    assert_raises(ArgumentError) { s.next_occurrences(Time.utc(2026, 1, 1), 0) }
    assert_raises(ArgumentError) { s.next_occurrences(Time.utc(2026, 1, 1), -1) }
  end
end

class TestImmutability < Minitest::Test
  def test_schedule_is_frozen
    assert CronParse.parse("* * * * *").frozen?
  end

  def test_field_arrays_are_frozen
    assert CronParse.parse("* * * * *").minutes.frozen?
  end
end
