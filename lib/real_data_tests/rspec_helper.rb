module RealDataTests
  module RSpecHelper
    # Loads a SQL dump using the given strategy (default: psql shell-out,
    # matching pre-0.5 behavior — data commits outside the caller's
    # transaction). Pass a different strategy to change how the dump is
    # executed, e.g. transactional loading on the ActiveRecord connection:
    #
    #   load_real_test_data("dump", strategy: RealDataTests::LoadStrategies::Native)
    def load_real_test_data(name, strategy: LoadStrategies::Psql)
      dump_path = File.join(RealDataTests.configuration.dump_path, "#{name}.sql")
      raise Error, "Test data file not found: #{dump_path}" unless File.exist?(dump_path)

      strategy.call(dump_path)
    end

    # Loads a SQL dump on the ActiveRecord connection
    # (LoadStrategies::Native), so the data participates in the caller's
    # transaction (e.g. DatabaseCleaner's :transaction strategy) and rolls
    # back with it. Shorthand for:
    #
    #   load_real_test_data(name, strategy: RealDataTests::LoadStrategies::Native)
    #
    # Unlike the default psql strategy, this never commits outside the test
    # transaction, but it cannot process psql meta-commands (e.g. \set) and
    # reads the whole dump into memory.
    def load_real_test_data_native(name)
      load_real_test_data(name, strategy: LoadStrategies::Native)
    end
  end
end
