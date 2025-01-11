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

      # Build dependency graph, but handle circular dependencies
      dependencies = {}
      tables.each do |table|
        model = table.classify.safe_constantize
        next unless model

        # Get foreign key constraints from database instead of model associations
        foreign_keys = ActiveRecord::Base.connection.foreign_keys(table).map(&:to_table)
        dependencies[table] = foreign_keys
      end

      # Set up deletion order based on dependencies
      deletion_order = reverse_topological_sort(dependencies)

      # Configure DatabaseCleaner strategy
      DatabaseCleaner.strategy = :deletion, { delete_order: deletion_order }
    end

    def reverse_topological_sort(dependencies)
      sorted = []
      visited = Set.new
      temporary = Set.new

      dependencies.each_key do |table|
        next if visited.include?(table)
        safe_visit_node(table, dependencies, sorted, visited, temporary)
      end

      sorted.reverse
    end

    def safe_visit_node(node, dependencies, sorted, visited, temporary)
      return if visited.include?(node)

      # If we detect a cycle, just continue without raising an error
      return if temporary.include?(node)

      temporary.add(node)

      (dependencies[node] || []).each do |dependency|
        next if visited.include?(dependency)
        safe_visit_node(dependency, dependencies, sorted, visited, temporary)
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
      options << "-q"
      options.join(" ")
    end
  end
end