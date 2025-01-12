# frozen_string_literal: true

require_relative "lib/real_data_tests/version"

Gem::Specification.new do |spec|
  spec.name = "real_data_tests"
  spec.version = RealDataTests::VERSION
  spec.authors = ["Kevin Dias"]
  spec.email = ["diasks2@gmail.com"]

  spec.summary = "Create realistic test data from local db records"
  spec.description = "A Ruby gem that helps create test data by analyzing and extracting real records and their associations from your database."
  spec.homepage = "https://github.com/diasks2/real_data_tests"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 5.0"
  spec.add_dependency "activerecord", ">= 5.0"
  spec.add_dependency "thor", "~> 1.0"
  spec.add_dependency "pg", ">= 1.1"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "database_cleaner", "~> 2.0"
  spec.add_dependency "faker", "~> 3.0"
end