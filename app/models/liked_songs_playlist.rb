# frozen_string_literal: true

class LikedSongsPlaylist < Playlist
  validate :only_one_per_user

  def spotify_page_size
    50
  end

  def liked_songs?
    true
  end

  def spotify_id
    nil
  end

  private

  def only_one_per_user
    existing = LikedSongsPlaylist.where(user_id: user_id)
    existing = existing.where.not(id: id) if persisted?

    errors.add(:base, "User already has a Liked Songs playlist") if existing.exists?
  end
end
