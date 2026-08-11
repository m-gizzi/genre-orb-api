# frozen_string_literal: true

module SmartPlaylists
  module PushStrategies
    def self.for(push_session, batches: PushBatches.new(push_session))
      push_session.strategy_replace? ? Replace.new(batches) : Diff.new(batches)
    end

    class Diff
      def initialize(batches)
        @batches = batches
      end

      def clear?
        false
      end

      def remove_slices
        batches.slices(batches.diff.to_remove)
      end

      def remove_batch_count
        remove_slices.size
      end

      def add_slices
        batches.slices(batches.diff.to_add)
      end

      private

      attr_reader :batches
    end

    class Replace
      def initialize(batches)
        @batches = batches
      end

      def clear?
        true
      end

      def seed_slice
        batches.slices(batches.desired).first || []
      end

      def remove_slices
        []
      end

      def remove_batch_count
        1
      end

      def add_slices
        batches.slices(batches.desired).drop(1)
      end

      private

      attr_reader :batches
    end
  end
end
