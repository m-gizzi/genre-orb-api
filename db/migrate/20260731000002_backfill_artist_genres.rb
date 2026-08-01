# frozen_string_literal: true

class BackfillArtistGenres < ActiveRecord::Migration[8.1]
  def up
    Artist.where.not(metadata: nil).select(:id, :metadata).find_in_batches(batch_size: 500) do |artists|
      pairs = artists.flat_map do |artist|
        (artist.metadata["genres"] || []).map { |name| { artist_id: artist.id, genre_name: name } }
      end
      Spotify::ArtistGenrePropagator.new.call(pairs)
    end
  end

  def down
    ArtistGenre.delete_all
  end
end
