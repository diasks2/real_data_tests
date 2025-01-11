module RealDataTests
  module RSpecHelper
    def load_real_test_data(name)
      dump_path = File.join(RealDataTests.configuration.dump_path, "#{name}.sql")
      raise Error, "Test data file not found: #{dump_path}" unless File.exist?(dump_path)

      ActiveRecord::Base.transaction do
        # Disable foreign key checks
        ActiveRecord::Base.connection.execute('SET session_replication_role = replica;')

        begin
          # Load the SQL dump quietly
          result = system("psql #{connection_options} -q < #{dump_path}")
          raise Error, "Failed to load test data: #{dump_path}" unless result

        ensure
          # Re-enable foreign key checks
          ActiveRecord::Base.connection.execute('SET session_replication_role = DEFAULT;')
        end
      end

      # Register tables for DatabaseCleaner dependency order
      register_tables_for_cleaning if defined?(DatabaseCleaner)
    end

    private

    def register_tables_for_cleaning
      # Get all tables that have data
      tables = ActiveRecord::Base.connection.tables

      # Build dependency graph
      dependencies = {}
      tables.each do |table|
        model = table.classify.safe_constantize
        next unless model

        dependencies[table] = model.reflect_on_all_associations(:belongs_to).map do |assoc|
          assoc.klass.table_name
        end
      end

      # Set DatabaseCleaner deletion order
      sorted_tables = topological_sort(dependencies).reverse
      DatabaseCleaner.clean_with(:deletion, only: sorted_tables)
    end

    def topological_sort(dependencies)
      sorted = []
      visited = Set.new
      temporary = Set.new

      dependencies.keys.each do |table|
        visit_node(table, dependencies, sorted, visited, temporary)
      end

      sorted
    end

    def visit_node(node, dependencies, sorted, visited, temporary)
      return if visited.include?(node)
      raise "Circular dependency detected" if temporary.include?(node)

      temporary.add(node)

      (dependencies[node] || []).each do |dependency|
        visit_node(dependency, dependencies, sorted, visited, temporary)
      end

      temporary.delete(node)
      visited.add(node)
      sorted << node
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
      # Add quiet flag to suppress INSERT messages
      options << "-q"
      options.join(" ")
    end
  end
end