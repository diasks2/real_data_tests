require 'csv'
require 'tmpdir'
require 'fileutils'
require 'json'

module RealDataTests
  class PgDumpGenerator
    def initialize(records)
      @records = records
    end

    def generate
      sorted_records = sort_by_dependencies(@records)
      insert_statements = collect_inserts(sorted_records)
      insert_statements.join("\n")
    end

    private

    def sort_by_dependencies(records)
      tables_with_records = records.group_by(&:class)
      dependencies = build_dependency_graph(tables_with_records.keys)
      sorted_models = topological_sort(dependencies)

      sorted_models.flat_map { |model| tables_with_records[model] || [] }
    end

    def build_dependency_graph(models)
      models.each_with_object({}) do |model, deps|
        deps[model] = model.reflect_on_all_associations(:belongs_to)
          .reject(&:polymorphic?)
          .map(&:klass)
          .uniq
      end
    end

    def topological_sort(dependencies)
      sorted = []
      visited = Set.new
      temporary = Set.new

      dependencies.each_key do |model|
        visit_model(model, dependencies, sorted, visited, temporary) unless visited.include?(model)
      end

      sorted.reverse
    end

    def visit_model(model, dependencies, sorted, visited, temporary)
      return if visited.include?(model)
      raise "Circular dependency detected" if temporary.include?(model)

      temporary.add(model)

      (dependencies[model] || []).each do |dependency|
        unless visited.include?(dependency)
          visit_model(dependency, dependencies, sorted, visited, temporary)
        end
      end

      temporary.delete(model)
      visited.add(model)
      sorted << model
    end

    def collect_inserts(records)
      records.map do |record|
        columns = record.class.column_names
        values = columns.map { |col| quote_value(record[col], get_column_type(record.class, col)) }

        <<~SQL
          INSERT INTO #{record.class.table_name}
          (#{columns.join(', ')})
          VALUES (#{values.join(', ')})
          ON CONFLICT (id) DO NOTHING;
        SQL
      end
    end

    def get_column_type(model, column_name)
      model.columns_hash[column_name].type
    end

    def quote_value(value, column_type)
      return 'NULL' if value.nil?

      case column_type
      when :integer, :decimal, :float
        value.to_s
      when :boolean
        value.to_s
      when :array
        array_value = value.is_a?(String) ? JSON.parse(value) : value
        format_array(array_value)
      when :json, :jsonb
        json_value = value.is_a?(String) ? value : value.to_json
        sanitize_string(json_value)
      else
        sanitize_string(value.to_s)
      end
    end

    def format_array(array)
      return "ARRAY[]::integer[]" if array.empty?

      elements = array.map do |element|
        case element
        when String
          sanitize_string(element)
        when Numeric
          element.to_s
        when nil
          'NULL'
        else
          sanitize_string(element.to_s)
        end
      end

      "ARRAY[#{elements.join(',')}]"
    end

    def sanitize_string(str)
      "'#{str.gsub("'", "''")}'"
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
      options << "-q"
      options.join(" ")
    end
  end
end