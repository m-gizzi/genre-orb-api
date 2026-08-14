# frozen_string_literal: true

module Genres
  class TrackGenreSql
    include SqlFragments

    COLUMNS = "id, track_id, genre_id, source, confidence"

    def initialize(user, preferences, overrides)
      @user = user
      @preferences = preferences
      @overrides = overrides
    end

    def call
      [claims, artist_additions, track_additions].compact.join(" UNION ALL ")
    end

    private

    attr_reader :user, :preferences, :overrides

    def claims
      "SELECT #{COLUMNS} FROM track_genres WHERE #{conditions.join(" AND ")}"
    end

    def conditions
      clauses = Layers.new(preferences, "track_genres").all + [artist_claim, track_hide_exclusion]
      clauses.compact.presence || ["TRUE"]
    end

    # Hiding a genre on an artist says "this artist is not that", not "this track is not
    # that" — so the track keeps the genre while some *other* credited artist still claims
    # it. That makes this an EXISTS over the remaining artists, not a NOT EXISTS over the
    # hidden ones, and it is why a collaboration survives hiding one of its artists.
    def artist_claim
      return nil unless overrides.artist_hides?

      sanitize(<<~SQL.squish, user.id, hidden)
        EXISTS (SELECT 1 FROM track_artists ta
                JOIN artist_genres ag ON ag.artist_id = ta.artist_id
                                     AND ag.genre_id = track_genres.genre_id
                                     AND ag.source = track_genres.source
                WHERE ta.track_id = track_genres.track_id
                  #{artist_layers}
                  AND NOT EXISTS (SELECT 1 FROM artist_genre_overrides o
                                  WHERE o.user_id = ? AND o.action = ?
                                    AND o.artist_id = ta.artist_id
                                    AND o.genre_id = ag.genre_id))
      SQL
    end

    # The blocklist is genre-level and already applied to track_genres.genre_id outside,
    # so only the per-row layers need repeating against the artist rows.
    def artist_layers
      layers = Layers.new(preferences, "ag")
      [layers.source_filter, layers.confidence_floor].compact.map { |clause| "AND #{clause}" }.join(" ")
    end

    def track_hide_exclusion
      return nil unless overrides.track_hides?

      sanitize(<<~SQL.squish, user.id, hidden)
        NOT EXISTS (SELECT 1 FROM track_genre_overrides o
                    WHERE o.user_id = ? AND o.action = ?
                      AND o.track_id = track_genres.track_id
                      AND o.genre_id = track_genres.genre_id)
      SQL
    end

    def artist_additions
      return nil unless overrides.artist_adds?

      sanitize(<<~SQL.squish, user.id, added)
        SELECT DISTINCT NULL::bigint AS id, ta.track_id, o.genre_id,
               #{user_source} AS source, #{full_confidence} AS confidence
        FROM artist_genre_overrides o
        JOIN track_artists ta ON ta.artist_id = o.artist_id
        WHERE o.user_id = ? AND o.action = ? #{track_override_exclusion}
      SQL
    end

    def track_override_exclusion
      return "" unless overrides.any_track?

      sanitize(<<~SQL.squish, user.id)
        AND NOT EXISTS (SELECT 1 FROM track_genre_overrides t
                        WHERE t.user_id = ? AND t.track_id = ta.track_id
                          AND t.genre_id = o.genre_id)
      SQL
    end

    def track_additions
      return nil unless overrides.track_adds?

      sanitize(<<~SQL.squish, user.id, added)
        SELECT NULL::bigint AS id, o.track_id, o.genre_id,
               #{user_source} AS source, #{full_confidence} AS confidence
        FROM track_genre_overrides o
        WHERE o.user_id = ? AND o.action = ?
      SQL
    end
  end
end
