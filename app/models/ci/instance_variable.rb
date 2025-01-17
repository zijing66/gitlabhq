# frozen_string_literal: true

module Ci
  class InstanceVariable < Ci::ApplicationRecord
    include Ci::NewHasVariable
    include Ci::Maskable
    include Limitable

    self.limit_name = 'ci_instance_level_variables'
    self.limit_scope = Limitable::GLOBAL_SCOPE

    alias_attribute :secret_value, :value

    validates :key, uniqueness: {
      message: -> (object, data) { _("(%{value}) has already been taken") }
    }

    validates :value, length: {
      maximum: 10_000,
      too_long: -> (object, data) do
        _('The value of the provided variable exceeds the %{count} character limit')
      end
    }

    scope :unprotected, -> { where(protected: false) }

    after_commit { self.class.invalidate_memory_cache(:ci_instance_variable_data) }

    class << self
      def all_cached
        cached_data[:all]
      end

      def unprotected_cached
        cached_data[:unprotected]
      end

      def invalidate_memory_cache(key)
        cache_backend.delete(key)
      end

      private

      def cached_data
        cache_backend.fetch(:ci_instance_variable_data, expires_in: 30.seconds) do
          all_records = unscoped.all.to_a

          { all: all_records, unprotected: all_records.reject(&:protected?) }
        end
      end

      def cache_backend
        Gitlab::ProcessMemoryCache.cache_backend
      end
    end
  end
end
