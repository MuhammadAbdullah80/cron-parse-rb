# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name        = "cron_parse"
  spec.version     = "0.1.0"
  spec.authors     = ["Muhammad Abdullah"]
  spec.summary     = "Parse cron expressions and compute their next firing times."
  spec.description = "A dependency-free five-field cron parser: matches? and next_after, " \
                     "with names, steps, ranges, @shortcuts and cron's day-of-month/day-of-week rule."
  spec.homepage    = "https://github.com/MuhammadAbdullah80/cron-parse-rb"
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 3.0"

  spec.files       = ["lib/cron_parse.rb", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"
end
