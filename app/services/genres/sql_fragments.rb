# frozen_string_literal: true

module Genres
  # Shared vocabulary for the two effective-genres statements. The casts are explicit
  # because UNION ALL resolves its column types from every branch: a bare `1.0` is
  # `numeric`, which does not line up with `confidence`'s `double precision`.
  module SqlFragments
    private

    def user_source = "#{GenreSourced::SOURCES.fetch(:user)}::integer"
    def full_confidence = "1.0::double precision"

    def hidden = GenreOverridable::ACTIONS.fetch(:hidden)
    def added  = GenreOverridable::ACTIONS.fetch(:added)

    def sanitize(statement, *binds)
      ActiveRecord::Base.sanitize_sql_array([statement, *binds])
    end
  end
end
