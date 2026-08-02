# frozen_string_literal: true

class LikedSongsPlaylist < Playlist
  CANONICAL_NAME = "Liked Songs"

  validate :only_one_per_user
  validate :details_are_managed_by_spotify, on: :update

  def liked_songs?
    true
  end

  def spotify_id
    nil
  end

  private

  def details_are_managed_by_spotify
    errors.add(:name, "is managed by Spotify") if name_changed? && name != CANONICAL_NAME
    errors.add(:description, "is managed by Spotify") if description_changed? && description.present?
  end

  def only_one_per_user
    existing = LikedSongsPlaylist.where(user_id: user_id)
    existing = existing.where.not(id: id) if persisted?

    errors.add(:base, "User already has a Liked Songs playlist") if existing.exists?
  end
end
