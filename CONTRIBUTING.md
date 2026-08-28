# Contributing

## Running the tests

```
bundle install
bundle exec rake test
```

CI runs the same command on Ruby 3.1, 3.2 and 3.3. The gem has no runtime
dependencies and should keep it that way — `minitest` and `rake` are the only
development ones.

## What a change needs

**A test that fails before it.** Every behaviour in this parser exists because
some cron implementation does it that way, and the test is the record of which
one. A change with no test is a change nobody can safely revisit.

**A reason in the commit message, not just a description.** `git log` should
answer "why is it like this" without a trip to the issue tracker. The existing
history is the standard: what changed, and what would go wrong if it were done
the obvious way instead.

## Things that look like bugs and are not

Before filing these, note they are deliberate and tested:

- **`0 0 1 * MON` fires on the 1st *and* every Monday.** When both day-of-month
  and day-of-week are restricted, cron ORs them. Every other pair of fields is
  ANDed. This surprises people, and it is what cron does.
- **`5/10` means 5, 15, 25, … not just 5.** A step on a bare value runs to the
  end of the field, matching Vixie cron.
- **`17-9` is rejected rather than wrapping.** It reads as either "5pm to 9am"
  or a typo, and guessing wrong schedules a job at the wrong time.
- **`next_after` returns `nil` for `0 0 30 2 *`.** February has no 30th. The
  search gives up after five years rather than looping forever.
- **A time that already matches is not its own `next_after`.** It is strictly
  after, which is what a scheduler wants.

## Scope

This parses the classic five-field format. Things deliberately out of scope:

- seconds (the six-field Quartz variant)
- `L`, `W`, `#` and `?` from Quartz
- timezone handling beyond respecting the UTC-ness of the `Time` passed in

Any of those would be a reasonable separate gem. Adding them here would mean
this one could no longer promise it accepts exactly what `crontab` accepts.

## Style

`# frozen_string_literal: true` at the top of every file. Two-space indent, as
enforced by `.editorconfig`. No RuboCop config — if a style question comes up
twice, that is the moment to add one, not before.
