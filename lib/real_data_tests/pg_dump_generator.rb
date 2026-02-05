require 'csv'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'set'

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
      # Group records by their model class
      tables_with_records = records.group_by(&:class)

      # Build dependency graph directly from the models we have
      dependencies = build_dependency_graph(tables_with_records.keys)

      # Sort models based on dependencies
      sorted_models = topological_sort(dependencies)

      # Map back to the actual records in dependency order
      sorted_models.flat_map { |model| tables_with_records[model] || [] }
    end

    def build_dependency_graph(models)
      models.each_with_object({}) do |model, deps|
        # Get direct dependencies from belongs_to associations
        direct_dependencies = model.reflect_on_all_associations(:belongs_to)
          .reject(&:polymorphic?) # Skip polymorphic associations
          .reject do |assoc|
            RealDataTests.configuration.current_preset.prevent_reciprocal?(model, assoc.name)
          end
          .map(&:klass)
          .select { |klass| models.include?(klass) }
          .uniq

        # Handle HABTM associations
        habtm_dependencies = model.reflect_on_all_associations(:has_and_belongs_to_many)
          .map { |assoc| assoc.join_table_model }
          .compact
          .select { |join_model| models.include?(join_model) }
          .uniq

        deps[model] = (direct_dependencies + habtm_dependencies).uniq
      end
    end

    def topological_sort(dependencies)
      sorted = []
      visited = Set.new
      temporary = Set.new

      dependencies.each_key do |model|
        visit_model(model, dependencies, sorted, visited, temporary) unless visited.include?(model)
      end

      sorted
    end

    def visit_model(model, dependencies, sorted, visited, temporary)
      return if visited.include?(model)

      if temporary.include?(model)
        # Only raise if this isn't a prevented self-reference
        unless RealDataTests.configuration.current_preset.prevent_reciprocal?(model, model.model_name.singular)
          cycle = detect_cycle(model, dependencies, temporary)
          raise "Circular dependency detected: #{cycle.map(&:name).join(' -> ')}"
        end
        return
      end

      temporary.add(model)

      (dependencies[model] || []).each do |dependency|
        visit_model(dependency, dependencies, sorted, visited, temporary) unless visited.include?(dependency)
      end

      temporary.delete(model)
      visited.add(model)
      sorted << model
    end

    def detect_cycle(start_model, dependencies, temporary)
      cycle = [start_model]
      current = dependencies[start_model]&.find { |dep| temporary.include?(dep) }

      while current && current != start_model
        cycle << current
        current = dependencies[current]&.find { |dep| temporary.include?(dep) }
      end

      cycle << start_model if current == start_model
      cycle
    end

    def collect_inserts(records)
      records.map do |record|
        table_name = record.class.table_name
        columns = record.class.column_names

        values = columns.map do |column|
          if record.class.respond_to?(:defined_enums) && record.class.defined_enums.key?(column)
            raw_value = record.read_attribute_before_type_cast(column)
            raw_value.nil? ? 'NULL' : raw_value.to_s
          else
            quote_value(record[column], get_column_info(record.class, column))
          end
        end

        <<~SQL.strip
          INSERT INTO #{table_name}
          (#{columns.join(', ')})
          VALUES (#{values.join(', ')})
          ON CONFLICT (id) DO NOTHING;
        SQL
      end
    end

    def get_column_info(model, column_name)
      column = model.columns_hash[column_name]
      {
        type: column.type,
        sql_type: column.sql_type,
        array: column.array
      }
    end

    def quote_value(value, column_info)
      return 'NULL' if value.nil?

      case column_info[:type]
      when :integer, :decimal, :float
        value.to_s
      when :boolean
        value.to_s
      when :jsonb, :json
        if value.blank?
          "'{}'"  # Return empty JSON object for blank JSONB/JSON fields
        else
          sanitize_string(value.is_a?(String) ? value : value.to_json)
        end
      when :array
        parse_and_format_array(value, column_info[:sql_type])
      else
        if column_info[:array]
          parse_and_format_array(value, column_info[:sql_type])
        else
          sanitize_string(value.to_s)
        end
      end
    end

    def parse_and_format_special_type(value, column_info)
      if column_info[:array] || column_info[:type] == :array
        parse_and_format_array(value, column_info[:sql_type])
      else
        # Handle JSON/JSONB
        json_value = value.is_a?(String) ? value : value.to_json
        sanitize_string(json_value)
      end
    end

    def parse_and_format_array(value, sql_type)
      # Always cast empty or string representations of empty arrays to proper type
      if value.nil? || value == '[]' || value == '{}' || (value.is_a?(Array) && value.empty?)
        base_type = extract_base_type(sql_type)
        return "'{}'" + "::#{base_type}[]"
      end

      # Parse the array if it's a string
      array_value = case value
                   when String
                     begin
                       JSON.parse(value)
                     rescue JSON::ParserError
                       value.gsub(/[{}"]/, '').split(',')
                     end
                   when Array
                     value
                   else
                     [value]
                   end

      # Format the array elements
      elements = array_value.map do |element|
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

      base_type = extract_base_type(sql_type)
      "ARRAY[#{elements.join(',')}]::#{base_type}[]"
    end

    def extract_base_type(sql_type)
      case sql_type
      when /character varying\[\]/i, /varchar\[\]/i
        'varchar'
      when /text\[\]/i
        'text'
      when /integer\[\]/i
        'integer'
      when /bigint\[\]/i
        'bigint'
      when /jsonb\[\]/i
        'jsonb'
      when /json\[\]/i
        'json'
      else
        sql_type.sub(/\[\]$/, '')
      end
    end

    def format_array(value, column_info)
      # Handle empty arrays
      if value.nil? || value == '[]' || value == '{}' || (value.is_a?(Array) && value.empty?)
        return "'{}'" + "::character varying[]" if column_info[:type] == :string
        return "'{}'" + "::#{extract_base_type(column_info[:sql_type])}[]"
      end

      # Parse the array if it's a string
      array_value = case value
                   when String
                     begin
                       JSON.parse(value)
                     rescue JSON::ParserError
                       value.gsub(/[{}"]/, '').split(',')
                     end
                   when Array
                     value
                   else
                     [value]
                   end

      # Format array elements
      elements = array_value.map do |element|
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

      # Use character varying[] for string arrays
      array_type = if column_info[:type] == :string
                    'character varying[]'
                  else
                    "#{extract_base_type(column_info[:sql_type])}[]"
                  end

      "ARRAY[#{elements.join(',')}]::#{array_type}"
    end

    def extract_base_type(sql_type)
      case sql_type
      when /character varying\[\]/i, /varchar\[\]/i
        'character varying'
      when /text\[\]/i
        'text'
      when /integer\[\]/i
        'integer'
      when /bigint\[\]/i
        'bigint'
      when /jsonb\[\]/i
        'jsonb'
      when /json\[\]/i
        'json'
      else
        sql_type.sub(/\[\]$/, '')
      end
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
      options << "-q"  # Run quietly
      options.join(" ")
    end
  end
end