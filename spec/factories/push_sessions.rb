# frozen_string_literal: true

FactoryBot.define do
  factory :push_session do
    smart_playlist { association :smart_playlist, :with_rules }
    status { :pending }
    strategy { :diff }

    trait :running do
      status { :running }
      started_at { 1.minute.ago }
    end

    trait :completed do
      status { :completed }
      started_at { 5.minutes.ago }
      completed_at { 1.minute.ago }
    end

    trait :failed do
      status { :failed }
      started_at { 5.minutes.ago }
      completed_at { 1.minute.ago }
      error_message { "Push failed after retries" }
    end

    trait :with_batches do
      transient do
        remove_batches { 2 }
        add_batches { 3 }
      end

      running
      total_remove_batches { remove_batches }
      total_add_batches { add_batches }
    end
  end
end
