# frozen_string_literal: true

module Rules
  # Compiles one condition into `tracks.id IN (subquery)` — or NOT IN, for a
  # negated operator.
  #
  # Every condition becoming a track-id set is the engine's core invariant. It is
  # what makes negation possible and it collapses the duplicate rows that
  # `track_genres` produces for a genre carried by more than one source.
  #
  # Presence checks are the one exception: see CORRELATED.
  class ConditionCompiler
    DATE_ADDED = "date_added"

    # Fields whose rows live in a table other than `tracks`, keyed by the column
    # naming the track, so a presence check can correlate back to `tracks.id`.
    #
    # Only presence checks take this path. They compare nothing, so the id-set form
    # has to build every (track, value) row in the pool just to DISTINCT it away —
    # and `NOT IN` stops Postgres turning that back into an anti-join. Correlating
    # lets it stop at the first row per track. A value comparison is the opposite
    # case: its id set is small and selective, and one hash semi-join beats a probe
    # per candidate track, so those keep the id-set form below.
    #
    # The remaining fields (album, year, title, duration, popularity, explicit) are
    # scoped to `tracks` itself, where correlating would compare the row to itself.
    CORRELATED = {
      "genre" => "track_genres.track_id",
      "artist" => "track_artists.track_id",
      "playlist" => "playlist_version_tracks.track_id",
    }.freeze

    # Each entry says how to build the track ids a field can constrain:
    #   scope    — a relation with one row per (track, candidate value)
    #   column   — the attribute the predicate compares
    #   id       — the column naming the track within `scope`
    #   presence — `scope` without the join a value comparison needs, for the
    #              fields whose vocabulary offers is_set / is_not_set
    SOURCES = {
      "genre" => { scope: ->(genres) { genres.tracks.joins(:genre) },
                   presence: ->(genres) { genres.tracks },
                   column: -> { Genre.arel_table[:name] },
                   id: :track_id, },
      "artist" => { scope: ->(_genres) { TrackArtist.joins(:artist) },
                    presence: ->(_genres) { TrackArtist.all },
                    column: -> { Artist.arel_table[:name] },
                    id: :track_id, },
      "album" => { scope: ->(_genres) { Track.joins(:album) },
                   column: -> { Album.arel_table[:title] },
                   id: :id, },
      "year" => { scope: ->(_genres) { Track.joins(:album) },
                  column: -> { Album.arel_table[:release_year] },
                  id: :id, },
      "title" => { scope: ->(_genres) { Track.all },
                   column: -> { Track.arel_table[:title] },
                   id: :id, },
      "duration" => { scope: ->(_genres) { Track.all },
                      column: -> { Track.arel_table[:duration_ms] },
                      id: :id, },
      "popularity" => { scope: ->(_genres) { Track.all },
                        column: -> { Track.arel_table[:popularity] },
                        id: :id, },
      "explicit" => { scope: ->(_genres) { Track.all },
                      column: -> { Track.arel_table[:explicit] },
                      id: :id, },
      "playlist" => { scope: ->(_genres) { PlaylistVersionTrack.joins(playlist_version: :playlist_as_current) },
                      column: -> { Playlist.arel_table[:id] },
                      id: :track_id, },
    }.freeze

    def initialize(memberships, user)
      @memberships = memberships
      @genres = Genres::EffectiveScope.new(user)
    end

    def call(node)
      condition = Condition.new(node)
      key = CORRELATED[condition.field]
      return id_set(condition) unless key && condition.presence_check?

      exists(condition, key)
    end

    private

    attr_reader :memberships, :genres

    def id_set(condition)
      ids = track_ids(condition).arel
      column = Track.arel_table[:id]

      condition.negated? ? column.not_in(ids) : column.in(ids)
    end

    # Correlating pins the row to the track already under test, which is the same
    # bound `present_rows` gets from `candidate_track_ids` — so the narrowing is not
    # repeated here.
    def exists(condition, key)
      source = SOURCES.fetch(condition.field)
      rows = source.fetch(:presence, source[:scope]).call(genres)
                   .where("#{key} = tracks.id").select("1")
      node = Arel.sql("EXISTS (#{rows.to_sql})")

      # Both wrap the literal in parentheses of their own, so it composes inside an
      # AND/OR group either way.
      condition.negated? ? Arel::Nodes::Not.new(node) : Arel::Nodes::Grouping.new(node)
    end

    def track_ids(condition)
      return date_added_ids(condition) if condition.field == DATE_ADDED

      source = SOURCES.fetch(condition.field)
      matching(source, condition).distinct.select(source[:id])
    end

    def matching(source, condition)
      return present_rows(source) if condition.presence_check?

      source[:scope].call(genres).where(Predicates.call(condition, source[:column].call))
    end

    # A presence check compares nothing, so it needs neither the join reaching
    # the named entity nor the whole table behind it. Narrowing to the pool the
    # evaluator already bounds the outer query to cannot change the answer, and
    # keeps an unfiltered `NOT IN` off every other user's rows.
    def present_rows(source)
      source.fetch(:presence, source[:scope]).call(genres)
            .where(source[:id] => candidate_track_ids)
    end

    def candidate_track_ids
      memberships.reselect(PlaylistVersionTrack.arel_table[:track_id])
    end

    # date_added is the one field that is not a track attribute — `added_at`
    # lives on the membership row, so a track has one value per playlist it's in.
    # The earliest one wins, which makes it a HAVING over the grouped memberships
    # rather than a WHERE.
    def date_added_ids(condition)
      attribute = PlaylistVersionTrack.arel_table[:added_at].minimum
      memberships.having(Predicates.call(condition, attribute))
                 .reselect(PlaylistVersionTrack.arel_table[:track_id])
    end
  end
end
