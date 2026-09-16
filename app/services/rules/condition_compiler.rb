# frozen_string_literal: true

module Rules
  # Compiles one condition into `tracks.id IN (subquery)` — or NOT IN, for a
  # negated operator.
  #
  # Every condition becoming a track-id set is the engine's core invariant. It is
  # what makes negation possible and it collapses the duplicate rows that
  # `track_genres` produces for a genre carried by more than one source.
  #
  # Presence checks are the one exception: see #exists.
  class ConditionCompiler
    DATE_ADDED = "date_added"

    # Each entry says how to build the track ids a field can constrain:
    #   scope    — a relation with one row per (track, candidate value)
    #   column   — the attribute the predicate compares
    #   id       — the column naming the track within `scope`
    #   presence — `scope` without the join a value comparison needs. Required
    #              for every field whose vocabulary offers is_set / is_not_set,
    #              and reached through a foreign key rather than `tracks.id` —
    #              see #correlatable!
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
      return id_set(condition) unless condition.presence_check?

      present = exists(condition.field)
      condition.negated? ? Arel::Nodes::Not.new(present) : present
    end

    private

    attr_reader :memberships, :genres

    def id_set(condition)
      ids = track_ids(condition).arel
      column = Track.arel_table[:id]

      condition.negated? ? column.not_in(ids) : column.in(ids)
    end

    # A presence check compares nothing, so the id-set form has to build every
    # (track, value) row in the pool just to DISTINCT it away — and `NOT IN` stops
    # Postgres turning that back into an anti-join. Correlating to the track under
    # test lets it stop at the first row instead. A value comparison is the opposite
    # case: its id set is small and selective, and one hash semi-join beats a probe
    # per candidate track, so those keep the id-set form.
    #
    # Correlating is also the bound the pool used to supply, so no narrowing to
    # the evaluator's candidate tracks is repeated here.
    def exists(field)
      source = correlatable!(field)
      rows = source.fetch(:presence).call(genres)
      correlated = rows.where(rows.klass.arel_table[source[:id]].eq(Track.arel_table[:id]))
                       .select("1")

      Arel::Nodes::Exists.new(correlated.arel)
    end

    # Only a source rooted outside `tracks` can be correlated. One rooted at
    # `tracks` itself would compare a row to itself: `EXISTS (SELECT 1 FROM tracks
    # WHERE tracks.id = tracks.id)` is true for every track, so is_set would match
    # everything and is_not_set nothing, with no symptom to notice. Giving a field
    # presence operators therefore means giving its source a `presence:` relation
    # reached through a foreign key — and this refuses to compile rather than
    # answer wrongly if that pairing is ever broken.
    def correlatable!(field)
      source = SOURCES.fetch(field)
      return source if source[:presence] && source[:id] != :id

      raise ArgumentError, "#{field} has presence operators but no correlatable source"
    end

    def track_ids(condition)
      return date_added_ids(condition) if condition.field == DATE_ADDED

      source = SOURCES.fetch(condition.field)
      source[:scope].call(genres)
                    .where(Predicates.call(condition, source[:column].call))
                    .distinct.select(source[:id])
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
