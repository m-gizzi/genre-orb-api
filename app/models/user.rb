# frozen_string_literal: true

class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [:spotify]

  has_many :service_connections, dependent: :destroy
  has_one :spotify_connection, -> { spotify }, class_name: "ServiceConnection", dependent: :destroy

  enum :registration_source, { email: 0, spotify: 1 }, validate: true

  def spotify_connected?
    spotify_connection.present?
  end
end
