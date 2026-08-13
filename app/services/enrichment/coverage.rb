# frozen_string_literal: true

module Enrichment
  # Per-source coverage over the user's own library, for the Library page.
  #
  # A coverage figure, not progress: the drip is headless and has no session to poll,
  # so this is read on page load rather than watched. `pending` counts rows the drip
  # has created but not yet reached, plus artists it has not even enrolled.
  class Coverage
    STATE_KEYS = %w[matched unmatched errored].freeze

    def initialize(user)
      @user = user
    end

    def call
      GenreSourced::ENRICHMENT_SOURCES.index_with { |source| counts_for(source) }
    end

    private

    attr_reader :user

    def counts_for(source)
      by_state = state_counts.fetch(source.to_s, {})
      enrolled = by_state.values.sum

      {
        total: library_artist_count,
        fetched: fetched_counts.fetch(source.to_s, 0),
        matched: by_state.fetch("matched", 0),
        unmatched: by_state.fetch("unmatched", 0),
        errored: by_state.fetch("errored", 0),
        pending: library_artist_count - enrolled + by_state.fetch("pending", 0),
      }
    end

    def state_counts
      @state_counts ||= library_rows.group(:source, :state).count.each_with_object({}) do |entry, grouped|
        (source, state), count = entry
        (grouped[source] ||= {})[state] = count
      end
    end

    # Distinct from `matched`: a matched row has an identifier but may not have had its
    # genres read yet, which is the drip's two-phase shape showing through.
    def fetched_counts
      @fetched_counts ||= library_rows.where.not(fetched_at: nil).group(:source).count
    end

    def library_rows
      ArtistMetadataSource.where(artist_id: library_artist_ids)
    end

    def library_artist_ids
      @library_artist_ids ||= user.library_artists.reselect("artists.id")
    end

    def library_artist_count
      @library_artist_count ||= user.library_artists.count
    end
  end
end
