# frozen_string_literal: true

module Filters
  class Base
    include Filters::Sql

    SORT_NULLS = :directional

    def initialize(user, params)
      @user = user
      @params = params
    end

    private

    attr_reader :user, :params

    def search(relation, column)
      value = params[:search]
      return relation if value.blank?

      relation.where("#{column} ILIKE ?", contains(value))
    end

    def sort
      @sort ||= Filters::Sort.new(
        nodes: self.class::SORT_NODES,
        default: self.class::DEFAULT_SORT,
        params: params,
        nulls: self.class::SORT_NULLS,
      )
    end
  end
end
