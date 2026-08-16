# frozen_string_literal: true

module Genres
  class ArtistGenreSql
    include SqlFragments

    COLUMNS = "id, artist_id, genre_id, source, confidence"

    def initialize(user, preferences, overrides)
      @user = user
      @preferences = preferences
      @overrides = overrides
    end

    def call
      [claims, additions].compact.join(" UNION ALL ")
    end

    private

    attr_reader :user, :preferences, :overrides

    def claims
      "SELECT #{COLUMNS} FROM artist_genres WHERE #{conditions.join(" AND ")}"
    end

    def conditions
      clauses = Layers.new(preferences, "artist_genres").all + [hide_exclusion]
      clauses.compact.presence || ["TRUE"]
    end

    def hide_exclusion
      return nil unless overrides.artist_hides?

      sanitize(<<~SQL.squish, user.id, hidden)
        NOT EXISTS (SELECT 1 FROM artist_genre_overrides o
                    WHERE o.user_id = ? AND o.action = ?
                      AND o.artist_id = artist_genres.artist_id
                      AND o.genre_id = artist_genres.genre_id)
      SQL
    end

    def additions
      return nil unless overrides.artist_adds?

      sanitize(<<~SQL.squish, user.id, added)
        SELECT NULL::bigint AS id, o.artist_id, o.genre_id,
               #{user_source} AS source, #{full_confidence} AS confidence
        FROM artist_genre_overrides o
        WHERE o.user_id = ? AND o.action = ?
      SQL
    end
  end
end
