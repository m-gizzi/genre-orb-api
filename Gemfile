source "https://rubygems.org"

gem "rails", "~> 8.1.3"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "tzinfo-data", platforms: %i[windows jruby]
gem "bootsnap", require: false
gem "kamal", require: false
gem "thruster", require: false
gem "image_processing", "~> 1.2"
gem "rack-cors"
gem "devise"
gem "sidekiq"
gem "sidekiq-cron"
gem "strong_migrations"
gem "alba"

group :development do
  gem "bullet"
  gem "rails_best_practices"
  gem "reek"
end

group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "factory_bot_rails"
  gem "rspec-rails"
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
  gem "rubocop-rspec", require: false
  gem "rubocop-performance", require: false
end

group :test do
  gem "simplecov", require: false
  gem "webmock"
  gem "vcr"
  gem "shoulda-matchers"
  gem "database_cleaner-active_record"
end
