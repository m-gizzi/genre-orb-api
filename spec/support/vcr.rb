# frozen_string_literal: true

require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = "spec/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!

  config.ignore_localhost = true

  config.filter_sensitive_data("<SPOTIFY_CLIENT_ID>") { ENV.fetch("SPOTIFY_CLIENT_ID", nil) }
  config.filter_sensitive_data("<SPOTIFY_CLIENT_SECRET>") { ENV.fetch("SPOTIFY_CLIENT_SECRET", nil) }
  config.filter_sensitive_data("<SPOTIFY_ACCESS_TOKEN>") do |interaction|
    interaction.request.headers["Authorization"]&.first&.gsub("Bearer ", "")
  end

  config.default_cassette_options = {
    record: :new_episodes,
    match_requests_on: %i[method uri body],
  }
end
