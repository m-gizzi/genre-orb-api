# frozen_string_literal: true

module SourcedGenres
  def self.for(subject, params)
    params.fetch(:genres, {})
          .fetch(subject.id, Genres::Loader::EMPTY)
          .map { |entry| entry.to_h.stringify_keys }
  end
end
