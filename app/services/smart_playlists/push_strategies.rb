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
        @remove_slices ||= batches.slices(batches.diff.to_remove)
      end

      def remove_batch_count
        remove_slices.size
      end

      def add_slices
        @add_slices ||= batches.slices(batches.diff.to_add)
      end

      def total_batches
        remove_batch_count + add_slices.size
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
        desired_slices.first || []
      end

      def remove_slices
        []
      end

      def remove_batch_count
        1
      end

      def add_slices
        desired_slices.drop(1)
      end

      def total_batches
        remove_batch_count + add_slices.size
      end

      private

      attr_reader :batches

      def desired_slices
        @desired_slices ||= batches.slices(batches.desired)
      end
    end
  end
end
