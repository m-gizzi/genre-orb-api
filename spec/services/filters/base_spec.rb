# frozen_string_literal: true

require "rails_helper"

RSpec.describe Filters::Base do
  describe ".sort_nodes" do
    it "raises a clear error when a filter forgets to declare its sortable keys" do
      undeclared = Class.new(described_class) do
        def self.name
          "Undeclared::Filter"
        end
      end

      expect { undeclared.sort_nodes }
        .to raise_error(NotImplementedError, /Undeclared::Filter must declare sortable keys/)
    end

    it "exposes the declared nodes, default, and nulls policy" do
      declared = Class.new(described_class) do
        sorts({ "name" => -> { Genre.arel_table[:name] } }, default: "name", nulls: :none)
      end

      expect(declared.sort_nodes.keys).to eq(["name"])
      expect(declared.default_sort).to eq("name")
      expect(declared.sort_nulls).to eq(:none)
    end

    it "defaults the nulls policy to directional" do
      declared = Class.new(described_class) do
        sorts({ "name" => -> { Genre.arel_table[:name] } }, default: "name")
      end

      expect(declared.sort_nulls).to eq(:directional)
    end
  end
end
