# frozen_string_literal: true

module PlaylistVersions
  class Pruner
    VERSIONS_KEPT = 3
    PLAYLIST_CHUNK = 200
    VERSION_BATCH = 200
    DEFAULT_BUDGET = 120.seconds

    GRACE = 1.hour

    Result = Struct.new(
      :playlists,
      :versions,
      :tracks,
      :pinned,
      :conflicts,
      :exhausted,
      :skipped,
      keyword_init: true,
    ) do
      def to_s
        return "skipped=true" if skipped

        "playlists=#{playlists} versions=#{versions} tracks=#{tracks} " \
          "pinned=#{pinned} conflicts=#{conflicts} exhausted=#{exhausted}"
      end
    end

    def initialize(deadline: DEFAULT_BUDGET.from_now, keep: VERSIONS_KEPT)
      @deadline = deadline
      @keep = keep
      @tally = { playlists: 0, versions: 0, tracks: 0, pinned: 0, conflicts: 0 }
    end

    def call
      return Result.new(skipped: true) if ScheduledRun.active.exists?

      exhausted = sweep
      Result.new(**tally, exhausted: exhausted, skipped: false)
    end

    private

    attr_reader :deadline, :keep, :tally

    def sweep
      cursor = 0

      loop do
        playlist_ids = next_playlist_ids(cursor)
        return false if playlist_ids.empty?

        cursor = playlist_ids.last
        tally[:playlists] += playlist_ids.size
        prune(playlist_ids)

        return true if past_deadline?
      end
    end

    def next_playlist_ids(cursor)
      Playlist.where(id: (cursor + 1)..).order(:id).limit(PLAYLIST_CHUNK).pluck(:id)
    end

    def prune(playlist_ids)
      candidates = PruneCandidates.new(playlist_ids, keep: keep, before: GRACE.ago).call
      unpinned(candidates).each_slice(VERSION_BATCH) do |ids|
        break if past_deadline?

        delete_batch(ids)
      end
    end

    # Subtracted in Ruby rather than joined in SQL: as a NOT IN it would match nothing the
    # moment a nullable baseline_version_id put a NULL in the set, and as correlated NOT
    # EXISTS clauses it would be four extra subplans per chunk. The set is small — a
    # partial unique index caps active pushes at one per smart playlist. BatchDelete
    # checks again under the lock; this only stops pinned ids wasting batch slots.
    def unpinned(candidates)
      pinned = SessionReferences.pinned_ids
      kept, dropped = candidates.partition { |id| pinned.exclude?(id) }
      tally[:pinned] += dropped.size
      kept
    end

    def delete_batch(ids)
      outcome = BatchDelete.new(ids).call
      tally[:versions] += outcome.versions
      tally[:tracks] += outcome.tracks
      tally[:conflicts] += 1 if outcome.conflicted
    end

    def past_deadline?
      Time.current >= deadline
    end
  end
end
