# frozen_string_literal: true

FactoryBot.define do
  factory :service_connection do
    user
    service_type { :spotify }
    service_user_id { "spotify_#{SecureRandom.hex(8)}" }
    access_token { SecureRandom.hex(32) }
    refresh_token { SecureRandom.hex(32) }
    token_expires_at { 1.hour.from_now }
    profile_data do
      {
        display_name: "Test User",
        email: "test@example.com",
        images: [],
        country: "US",
        product: "premium",
      }
    end
  end
end
