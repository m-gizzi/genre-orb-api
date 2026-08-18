# frozen_string_literal: true

module Rules
  # Compiles one condition into `tracks.id IN (subquery)` — or NOT IN, for a
  # negated operator.
  #
  # Every condition becoming a track-id set is the engine's core invariant. It is
  # what makes negation possible and it collapses the duplicate rows that
  # `track_genres` produces for a genre carried by more than one source.
  class ConditionCompiler
    DATE_ADDED = "date_added"

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
      ids = track_ids(condition).arel
      column = Track.arel_table[:id]

      condition.negated? ? column.not_in(ids) : column.in(ids)
    end

    private

    attr_reader :memberships, :genres

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
