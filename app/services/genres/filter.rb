# frozen_string_literal: true

module Genres
  class Filter < Filters::Base
    SORT_NODES = {
      "name" => -> { Genre.arel_table[:name] },
    }.freeze

    DEFAULT_SORT = "name"
    SORT_NULLS = :none

    def call
      relation = search(user.library_genres, Genre.arel_table[:name])
      relation.order(*sort.terms)
    end
  end
end
