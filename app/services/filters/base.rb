# frozen_string_literal: true

module Filters
  class Base
    include Filters::Sql

    class << self
      attr_reader :default_sort, :sort_nulls

      def sorts(nodes, default:, nulls: :directional)
        @sort_nodes = nodes.freeze
        @default_sort = default
        @sort_nulls = nulls
      end

      def sort_nodes
        @sort_nodes || raise(NotImplementedError, "#{name} must declare sortable keys with `sorts`")
      end
    end

    def initialize(user, params)
      @user = user
      @params = params
    end

    private

    attr_reader :user, :params

    def search(relation, column)
      value = params[:search]
      return relation if value.blank?

      relation.where(column.matches(contains(value)))
    end

    def sort
      @sort ||= Filters::Sort.new(
        nodes: self.class.sort_nodes,
        default: self.class.default_sort,
        params: params,
        nulls: self.class.sort_nulls,
      )
    end
  end
end
