# frozen_string_literal: true

class SpotifyOauthService
  Result = Struct.new(:success?, :user, :service_connection, :error, keyword_init: true)

  def initialize(current_user, auth_hash)
    @current_user = current_user
    @auth_hash = auth_hash
  end

  def call
    ActiveRecord::Base.transaction do
      validate_not_linked_to_other_user!

      user = resolve_user
      service_connection = upsert_service_connection(user)

      Result.new(
        success?: true,
        user: user,
        service_connection: service_connection,
      )
    end
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success?: false, error: e.message)
  rescue StandardError => e
    Rails.logger.error("SpotifyOauthService error: #{e.message}")
    Result.new(success?: false, error: "Failed to connect Spotify account")
  end

  private

  attr_reader :current_user, :auth_hash

  def existing_connection
    return @existing_connection if defined?(@existing_connection)

    @existing_connection = ServiceConnection.find_by(
      service_type: :spotify,
      service_user_id: spotify_uid,
    )
  end

  def validate_not_linked_to_other_user!
    return unless existing_connection
    return unless current_user
    return if existing_connection.user_id == current_user.id

    raise ActiveRecord::RecordInvalid.new(existing_connection),
          "This Spotify account is already linked to another user"
  end

  def resolve_user
    return current_user if current_user.present?
    return existing_connection.user if existing_connection

    find_or_create_user_by_email
  end

  def find_or_create_user_by_email
    if spotify_email.present?
      user = User.find_by(email: spotify_email)
      return user if user
    end

    User.create!(
      email: spotify_email || "#{spotify_uid}@spotify.genreorb.local",
      password: SecureRandom.hex(16),
      registration_source: :spotify,
    )
  end

  def upsert_service_connection(user)
    connection = existing_connection || user.service_connections.build(service_type: :spotify)

    connection.update!(
      service_user_id: spotify_uid,
      access_token: credentials["token"],
      refresh_token: credentials["refresh_token"],
      token_expires_at: Time.zone.at(credentials["expires_at"]),
      profile_data: build_profile_data,
    )

    connection
  end

  def credentials
    auth_hash["credentials"]
  end

  def info
    auth_hash["info"]
  end

  def spotify_uid
    auth_hash["uid"]
  end

  def spotify_email
    info["email"]
  end

  def build_profile_data
    {
      display_name: info["name"],
      email: info["email"],
      images: info["images"],
      country: info["country"],
      product: info["product"],
      external_urls: auth_hash.dig("extra", "raw_info", "external_urls"),
    }
  end
end
