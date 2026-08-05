# frozen_string_literal: true

module SmartPlaylists
  # Chaining is allowed — a smart playlist may draw from another's target — so
  # cycles are reachable. This models the flow of tracks between a user's
  # playlists as a directed graph, one edge per (source → target).
  #
  # `excluding:` drops one smart playlist's edges, so a record being re-saved is
  # tested against the graph *without* the edges it is about to replace.
  class DependencyGraph
    def initialize(user, excluding: nil)
      @user = user
      @excluding = excluding
    end

    # Does anything already flow from `origin` to `destination`? Breadth-first
    # with a visited set, so it terminates even if the stored graph is somehow
    # already cyclic.
    def reaches?(origin, destination)
      return true if origin == destination

      visited = Set.new([origin])
      queue = [origin]

      until queue.empty?
        edges_from(queue.shift).each do |node|
          return true if node == destination

          queue << node if visited.add?(node)
        end
      end

      false
    end

    private

    attr_reader :user, :excluding

    def edges_from(playlist_id)
      edges.fetch(playlist_id, [])
    end

    def edges
      @edges ||= pairs.each_with_object({}) do |(source_id, target_id), map|
        (map[source_id] ||= []) << target_id
      end
    end

    def pairs
      scope = SmartPlaylist.joins(:target_playlist, :smart_playlist_sources)
                           .where(playlists: { user_id: user.id })
      scope = scope.where.not(id: excluding) if excluding
      scope.pluck("smart_playlist_sources.playlist_id", :target_playlist_id)
    end
  end
end
