require 'csv'
require 'tmpdir'
require 'fileutils'

module RealDataTests
  class PgDumpGenerator
    def initialize(records)
      @records = records
    end

    def generate
      # Sort records by their dependencies
      sorted_records = sort_by_dependencies(@records)
      insert_statements = collect_inserts(sorted_records)

      # Write all INSERT statements, no schema or grants
      insert_statements.join("\n")
    end

    private

    def sort_by_dependencies(records)
      # Group records by table
      tables_with_records = records.group_by { |record| record.class }

      # Build dependency graph
      dependencies = {}
      tables_with_records.keys.each do |model|
        dependencies[model] = model.reflect_on_all_associations(:belongs_to).map do |assoc|
          assoc.klass
        end
      end

      # Topologically sort models based on dependencies
      sorted_models = topological_sort(dependencies)

      # Return records in sorted order
      sorted_models.flat_map do |model|
        tables_with_records[model] || []
      end
    end

    def topological_sort(dependencies)
      sorted = []
      visited = Set.new
      temporary = Set.new

      dependencies.keys.each do |model|
        visit_model(model, dependencies, sorted, visited, temporary)
      end

      sorted.reverse
    end

    def visit_model(model, dependencies, sorted, visited, temporary)
      return if visited.include?(model)
      raise "Circular dependency detected" if temporary.include?(model)

      temporary.add(model)

      dependencies[model].each do |dependency|
        visit_model(dependency, dependencies, sorted, visited, temporary)
      end

      temporary.delete(model)
      visited.add(model)
      sorted << model
    end

    def collect_inserts(records)
      records.map do |record|
        columns = record.class.column_names
        values = columns.map { |col| quote_value(record.send(col)) }

        "INSERT INTO #{record.class.table_name} (#{columns.join(', ')}) " \
        "VALUES (#{values.join(', ')}) " \
        "ON CONFLICT (id) DO NOTHING;"
      end
    end

    def quote_value(value)
      return 'NULL' if value.nil?
      return value if value =~ /^\d+$/  # If it's a number
      "'#{value.to_s.gsub("'", "''")}'" # Escape single quotes for PostgreSQL
    end

    def connection_options
      config = if ActiveRecord::Base.respond_to?(:connection_db_config)
        ActiveRecord::Base.connection_db_config.configuration_hash
      else
        ActiveRecord::Base.connection_config
      end

      options = []
      options << "-h #{config[:host]}" if config[:host]
      options << "-p #{config[:port]}" if config[:port]
      options << "-U #{config[:username]}" if config[:username]
      options << "-d #{config[:database]}"
      options.join(" ")
    end
  end
end