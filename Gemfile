# frozen_string_literal: true

source "https://rubygems.org"

gem "alba"
gem "bootsnap", require: false
gem "devise"
gem "faraday"
gem "faraday-net_http_persistent"
gem "image_processing", "~> 2.0"
gem "kamal", require: false
gem "omniauth"
gem "omniauth-rails_csrf_protection"
gem "omniauth-spotify"
gem "pagy", "~> 9.4"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "rack-cors"
gem "rails", "~> 8.1.3"
gem "sidekiq"
gem "sidekiq-cron"
gem "strong_migrations"
gem "thruster", require: false
gem "tzinfo-data", platforms: %i[windows jruby]

group :development do
  gem "bullet"
  gem "rails_best_practices"
  gem "reek"
end

group :development, :test do
  gem "brakeman", require: false
  gem "bundler-audit", require: false
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "dotenv-rails"
  gem "factory_bot_rails"
  gem "rspec-rails"
  gem "rubocop", require: false
  gem "rubocop-factory_bot", require: false
  gem "rubocop-performance", require: false
  gem "rubocop-rails", require: false
  gem "rubocop-rspec", require: false
  gem "rubocop-rspec_rails", require: false
end

group :test do
  gem "database_cleaner-active_record"
  gem "shoulda-matchers"
  gem "simplecov", require: false
  gem "vcr"
  gem "webmock"
end
