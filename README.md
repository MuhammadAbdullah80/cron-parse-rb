# cron_parse

Parse a five-field cron expression, ask whether a time matches it, and compute
when it next fires. No dependencies outside the standard library.

```ruby
require "cron_parse"

schedule = CronParse.parse("*/15 9-17 * * MON-FRI")

schedule.matches?(Time.utc(2026, 3, 4, 9, 15))    # => true
schedule.next_after(Time.utc(2026, 3, 4, 9, 20))  # => 2026-03-04 09:30 UTC
schedule.next_occurrences(Time.now, 5)            # => [Time, Time, ...]
```

## Syntax

| Form | Example | Means |
| --- | --- | --- |
| wildcard | `*` | every value |
| single | `5` | just 5 |
| list | `0,15,30` | any of those |
| range | `9-17` | 9 through 17 |
| step over wildcard | `*/15` | 0, 15, 30, 45 |
| step over range | `1-10/3` | 1, 4, 7, 10 |
| step from a value | `5/10` | 5, 15, 25, ... to the end of the field |
| month name | `JAN`, `jun-aug` | case-insensitive |
| weekday name | `MON-FRI` | case-insensitive |

Shortcuts: `@yearly`, `@annually`, `@monthly`, `@weekly`, `@daily`,
`@midnight`, `@hourly`.

Both `0` and `7` mean Sunday, and they collapse to one value.

## Two behaviours worth knowing

**Day-of-month and day-of-week are ORed, not ANDed.** This is cron's oddest
rule, and it surprises people:

```ruby
s = CronParse.parse("0 0 1 * MON")
s.matches?(Time.utc(2026, 4, 1))  # true - the 1st, a Wednesday
s.matches?(Time.utc(2026, 4, 6))  # true - a Monday, not the 1st
```

When *both* day fields are restricted, either one matching is enough. When only
one is restricted, it alone decides. Every other pair of fields is ANDed.

**`5/10` runs to the end of the field.** A step on a bare value means "from here
onward", matching Vixie cron: `5/10` in the minute field is 5, 15, 25, 35, 45,
55 — not just 5.

## Errors

Malformed expressions raise `CronParse::ParseError` (a subclass of
`ArgumentError`) naming the field and the problem:

```
CronParse.parse("* 24 * * *")   # hour: 24 is out of range (0-23)
CronParse.parse("* 17-9 * * *") # hour: range "17-9" runs backwards (17 to 9)
CronParse.parse("*/0 * * * *")  # minute: step must be at least 1 in "*/0"
CronParse.parse("* * * SMARCH *") # month: "SMARCH" is not a number or a name
```

Wrapping ranges are rejected rather than silently reinterpreted, because
`17-9` reads as either "5pm to 9am" or a typo and guessing wrong schedules a job
at the wrong time.

## `next_after`

Returns the first matching time **strictly after** the argument, so a time that
already matches is not its own next occurrence. Seconds are truncated, not
rounded.

An expression that cannot fire returns `nil` rather than looping — the search
gives up after five years, which clears the worst legitimate case (`0 0 29 2 *`
fires only on a leap day) with slack to spare.

```ruby
CronParse.parse("0 0 29 2 *").next_after(Time.utc(2026, 3, 1))
# => 2028-02-29 00:00 UTC

CronParse.parse("0 0 30 2 *").next_after(Time.utc(2026, 1, 1))
# => nil
```

Day and month steps go through `Date` rather than adding 86_400 seconds, so a
daylight-saving transition cannot shift the result by an hour. The returned
`Time` keeps the UTC-ness of the one passed in.

## Tests

```
bundle install
bundle exec rake test
```

CI runs them on Ruby 3.1, 3.2 and 3.3.

## License

MIT
