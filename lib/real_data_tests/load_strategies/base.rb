# frozen_string_literal: true

module RealDataTests
  module LoadStrategies
    # Base class for dump loading strategies. Subclasses implement #call,
    # which receives the absolute path to the SQL dump file and executes it.
    #
    #   class MyStrategy < RealDataTests::LoadStrategies::Base
    #     def call(dump_path)
    #       # load the dump
    #     end
    #   end
    #
    #   load_real_test_data("dump", strategy: MyStrategy)
    class Base
      def self.call(dump_path)
        new.call(dump_path)
      end

      def call(dump_path)
        raise NotImplementedError, "#{self.class.name} must implement #call"
      end
    end
  end
end
