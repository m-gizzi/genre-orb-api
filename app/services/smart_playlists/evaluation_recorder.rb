# frozen_string_literal: true

module SmartPlaylists
  class EvaluationRecorder
    class NotReadyError < StandardError; end

    def initialize(smart_playlist)
      @smart_playlist = smart_playlist
    end

    def call
      raise NotReadyError unless smart_playlist.ready?

      matched = QueryTimeout.guard { Evaluator.new(smart_playlist).count }

      smart_playlist.update_columns(
        match_count: matched,
        last_evaluated_at: Time.current,
        updated_at: Time.current,
      )
      smart_playlist
    end

    private

    attr_reader :smart_playlist
  end
end
