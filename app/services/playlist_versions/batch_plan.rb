# frozen_string_literal: true

module PlaylistVersions
  # Packs `[id, track_count]` candidates into delete batches bounded by the rows they
  # will actually remove.
  #
  # Two ceilings, whichever binds first. TRACK_BUDGET is the one that usually does: a
  # single Liked Songs version can carry tens of thousands of rows, so batching on
  # version count alone would put over a million rows into one DELETE while BatchDelete
  # holds the locks for all of it. VERSION_BATCH still caps a batch of empty versions.
  #
  # A version whose own track count already exceeds the budget still gets a batch, alone
  # — it has to go through somehow, and BatchDelete's statement timeout is what bounds it
  # from there.
  class BatchPlan
    TRACK_BUDGET = 20_000
    VERSION_BATCH = 25

    def initialize(candidates)
      @candidates = candidates
    end

    def call
      packed.pluck(:ids)
    end

    private

    attr_reader :candidates

    def packed
      candidates.each_with_object([]) do |(id, track_count), acc|
        acc << { ids: [], rows: 0 } if acc.empty? || full?(acc.last, track_count)
        acc.last[:ids] << id
        acc.last[:rows] += track_count
      end
    end

    def full?(batch, track_count)
      batch[:ids].size >= VERSION_BATCH || batch[:rows] + track_count > TRACK_BUDGET
    end
  end
end
