# frozen_string_literal: true

module Desiru
  module Persistence
    module Repositories
      # Base repository with common CRUD operations
      class BaseRepository
        attr_reader :model_class

        def initialize(model_class)
          @model_class = model_class
        end

        def all
          dataset.all
        end

        def find(id)
          dataset.first(id: id)
        end

        def find_by(conditions)
          dataset.where(conditions).first
        end

        def where(conditions)
          dataset.where(conditions).all
        end

        def create(attributes)
          model_class.create(attributes)
        end

        def update(id, attributes)
          record = find(id)
          return nil unless record

          record.update(attributes)
          record
        end

        def delete?(id)
          record = find(id)
          return false unless record

          record.destroy
          true
        end

        def count
          dataset.count
        end

        def exists?(conditions)
          dataset.where(conditions).count.positive?
        end

        def paginate(page: 1, per_page: 20)
          dataset
            .limit(per_page)
            .offset((page - 1) * per_page)
            .all
        end

        protected

        def dataset
          model_class.dataset
        end

        def transaction(&)
          Database.transaction(&)
        end
      end
    end
  end
end
