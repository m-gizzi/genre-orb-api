# frozen_string_literal: true

module Genres
  class OverrideWriter
    MODELS = { "Track" => [TrackGenreOverride, :track], "Artist" => [ArtistGenreOverride, :artist] }.freeze

    class UnknownSubject < StandardError; end

    def initialize(user, subject)
      @user = user
      @model, @key = MODELS.fetch(subject.class.base_class.name) { raise UnknownSubject, subject.class.name }
      @subject = subject
    end

    def set(genre, action)
      record = model.find_or_initialize_by(scope.merge(genre: genre))
      record.action = action
      record.save!
      record
    end

    def clear(genre)
      model.where(scope.merge(genre: genre)).destroy_all
    end

    private

    attr_reader :user, :subject, :model, :key

    def scope
      { :user => user, key => subject }
    end
  end
end
