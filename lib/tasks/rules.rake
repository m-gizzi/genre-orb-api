# frozen_string_literal: true

namespace :rules do
  desc "Print the rule schema served to the builder UI"
  task schema: :environment do
    puts JSON.pretty_generate(Rules::FieldCatalog.to_h)
  end
end
