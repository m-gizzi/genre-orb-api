# frozen_string_literal: true

module Filters
  class Sort
    def initialize(nodes:, params:, default:, nulls: :directional)
      @nodes = nodes
      @params = params
      @default = default
      @nulls = nulls
    end

    def key
      @nodes.key?(@params[:sort].to_s) ? @params[:sort].to_s : @default
    end

    def terms(*extra)
      [primary, *extra]
    end

    private

    def primary
      directed = descending? ? node.desc : node.asc
      apply_nulls(directed)
    end

    def node
      @nodes.fetch(key).call
    end

    def apply_nulls(directed)
      case @nulls
      when :last then directed.nulls_last
      when :directional then descending? ? directed.nulls_last : directed.nulls_first
      else directed
      end
    end

    def descending?
      @params[:order].to_s.casecmp("desc").zero?
    end
  end
end
