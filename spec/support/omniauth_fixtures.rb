# frozen_string_literal: true

module OmniauthFixtures
  def spotify_omniauth_hash(overrides = {})
    {
      "uid" => "spotify_user_123",
      "info" => {
        "name" => "Test User",
        "email" => "spotify@example.com",
        "images" => [{ "url" => "https://example.com/avatar.jpg" }],
        "country" => "US",
        "product" => "premium",
      },
      "credentials" => {
        "token" => "access_token_abc",
        "refresh_token" => "refresh_token_xyz",
        "expires_at" => 1.hour.from_now.to_i,
      },
      "extra" => {
        "raw_info" => {
          "external_urls" => { "spotify" => "https://open.spotify.com/user/spotify_user_123" },
        },
      },
    }.deep_merge(overrides)
  end
end

RSpec.configure do |config|
  config.include OmniauthFixtures
end
