# frozen_string_literal: true

module Enrichment
  # Per-source coverage over the user's own library, for the Library page.
  #
  # A coverage figure, not progress: the drip is headless and has no session to poll,
  # so this is read on page load rather than watched. `pending` counts rows the drip
  # has created but not yet reached, plus artists it has not even enrolled.
  #
  # It rides along on the artist sync_status response, which is polled every couple of
  # seconds while a sync runs, so it stays down to one aggregate: every count comes
  # from a single grouped scan, and the caller passes in the library size it already
  # counted for its own payload.
  class Coverage
    STATES = ArtistMetadataSource.states.keys.freeze

    def initialize(user, library_artist_count: nil)
      @user = user
      @library_artist_count = library_artist_count
    end

    def call
      GenreSourced::ENRICHMENT_SOURCES.index_with { |source| counts_for(source) }
    end

    private

    attr_reader :user

    def counts_for(source)
      by_state = rollup.fetch(source.to_s, {})
      enrolled = STATES.sum { |state| by_state.fetch(state, 0) }

      {
        total: library_artist_count,
        fetched: by_state.fetch(:fetched, 0),
        matched: by_state.fetch("matched", 0),
        unmatched: by_state.fetch("unmatched", 0),
        errored: by_state.fetch("errored", 0),
        pending: library_artist_count - enrolled + by_state.fetch("pending", 0),
      }
    end

    # source => { <state> => count, fetched: count }.
    #
    # COUNT(fetched_at) counts only non-null, which is what makes `fetched` a second
    # projection of the same scan rather than a second query. It is distinct from
    # `matched`: a matched row has an identifier but may not have had its genres read
    # yet, which is the drip's two-phase shape showing through.
    def rollup
      @rollup ||= library_rows
                  .group(:source, :state)
                  .pluck(:source, :state, Arel.sql("COUNT(*)"), Arel.sql("COUNT(fetched_at)"))
                  .each_with_object({}) do |(source, state, total, fetched), grouped|
                    counts = (grouped[source] ||= Hash.new(0))
                    counts[state] += total
                    counts[:fetched] += fetched
                  end
    end

    def library_rows
      ArtistMetadataSource.where(artist_id: user.library_artists.reselect("artists.id"))
    end

    # Memoization doubles as the default, so a caller that has already counted the
    # library can hand the number over instead of paying for it twice.
    def library_artist_count
      @library_artist_count ||= user.library_artists.count
    end
  end
end
