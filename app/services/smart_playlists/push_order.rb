# frozen_string_literal: true

module SmartPlaylists
  # Kahn's algorithm over the user's playlist graph: each wave is a set of smart
  # playlists whose upstreams have all been pushed, so a wave's pushes can run
  # concurrently and the next wave reads their results.
  class PushOrder
    def initialize(user)
      @user = user
      @cyclic = false
    end

    def waves
      @waves ||= build_waves
    end

    def cyclic?
      waves
      @cyclic
    end

    private

    attr_reader :user

    def build_waves
      remaining = candidates.dup
      pushed = Set.new
      result = []

      until remaining.empty?
        wave = next_wave(remaining, pushed)
        result << wave
        wave.each { |smart_playlist| pushed << smart_playlist.target_playlist_id }
        remaining -= wave
      end

      result
    end

    # A stored cycle should be unreachable — SmartPlaylist validates against one —
    # but insert_all and update_column paths bypass validations, so degrade to
    # "push the remainder together" rather than looping forever.
    def next_wave(remaining, pushed)
      ready = remaining.select { |smart_playlist| prerequisites(smart_playlist).subset?(pushed) }
      return ready if ready.any?

      @cyclic = true
      Rails.logger.warn("PushOrder: cycle among smart playlists #{remaining.map(&:id).inspect}")
      remaining
    end

    def candidates
      @candidates ||= user.smart_playlists.enabled.includes(:target_playlist).select(&:ready?)
    end

    def candidate_targets
      @candidate_targets ||= candidates.map(&:target_playlist_id).to_set
    end

    def prerequisites(smart_playlist)
      upstreams.fetch(smart_playlist.target_playlist_id, Set.new)
    end

    # Edges point source → target; a candidate filling `target` therefore waits on
    # the candidate whose own target is `source`. Sources nobody fills are plain
    # synced playlists and impose no order.
    def upstreams
      @upstreams ||= DependencyGraph.new(user).edge_pairs.each_with_object({}) do |(source, target), map|
        next unless candidate_targets.include?(source)

        (map[target] ||= Set.new) << source
      end
    end
  end
end
