# frozen_string_literal: true

module Genres
  class Filter
    SORT_NODES = {
      "name" => -> { Genre.arel_table[:name] },
    }.freeze

    DEFAULT_SORT = "name"

    def initialize(user, params)
      @user = user
      @params = params
    end

    def call
      relation = user.library_genres
      relation = filter_search(relation)
      relation.order(order_term)
    end

    private

    attr_reader :user, :params

    def filter_search(relation)
      value = params[:search]
      return relation if value.blank?

      relation.where("genres.name ILIKE ?", contains(value))
    end

    def order_term
      node = SORT_NODES.fetch(sort_key).call
      descending? ? node.desc : node.asc
    end

    def sort_key
      SORT_NODES.key?(params[:sort].to_s) ? params[:sort].to_s : DEFAULT_SORT
    end

    def descending?
      params[:order].to_s.casecmp("desc").zero?
    end

    def contains(value)
      "%#{ActiveRecord::Base.sanitize_sql_like(value.to_s)}%"
    end
  end
end
