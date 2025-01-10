# Real Data Tests

Create realistic test data in your Rails applications by extracting real records and their associations from your development or production database.

## Why use Real Data Tests?

Testing with realistic data is crucial for catching edge cases and ensuring your application works with real-world data structures. However, creating complex test fixtures that accurately represent your data relationships can be time-consuming and error-prone.

Real Data Tests solves this by:
- Automatically analyzing and extracting real records and their associations
- Creating reusable SQL dumps that can be committed to your repository
- Making it easy to load realistic test data in your specs

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'real_data_tests'
```

And then execute:
```bash
$ bundle install
```

Or install it yourself as:
```bash
$ gem install real_data_tests
```

## Configuration

Create an initializer in your Rails application:

```ruby
# config/initializers/real_data_tests.rb
RealDataTests.configure do |config|
  # Directory where SQL dumps will be stored
  config.dump_path = 'spec/fixtures/real_data_dumps'

  # Optionally exclude specific associations from being collected
  config.excluded_associations = [:very_large_association]
end
```

## Usage

### 1. Preparing Test Data

You can create SQL dumps from your development or production database in two ways:

**From Rails console:**
```ruby
# Find a record you want to use as test data
user = User.find(1)

# Create a dump file including the user and all related records
RealDataTests.create_dump_file(user, name: "active_user_with_posts")
```

**Or from command line:**
```bash
$ bundle exec real_data_tests create_dump User 1 active_user_with_posts
```

This will:
1. Find the specified User record
2. Collect all associated records (posts, comments, etc.)
3. Generate a SQL dump file in your configured dump_path

### 2. Using in Tests

First, include the helper in your test setup:

```ruby
# spec/rails_helper.rb or spec/spec_helper.rb
require 'real_data_tests'

RSpec.configure do |config|
  config.include RealDataTests::RSpecHelper
end
```

Then use it in your tests:

```ruby
RSpec.describe "Blog" do
  it "displays user's posts correctly" do
    # Load the previously created dump file
    load_real_test_data("active_user_with_posts")

    # Your test code here - the database now contains
    # the user and all their associated records
    visit user_posts_path(User.first)
    expect(page).to have_content("My First Post")
  end
end
```

## How It Works

1. **Record Collection**: The gem analyzes your ActiveRecord associations to find all related records.
2. **Dump Generation**: It creates a PostgreSQL dump file containing only the necessary records.
3. **Test Loading**: During tests, it loads the dump file into your test database.

## Best Practices

1. **Version Control**: Commit your SQL dumps to version control so all developers have access to the same test data.
2. **Meaningful Names**: Use descriptive names for your dump files that indicate the scenario they represent.
3. **Data Privacy**: Be careful not to commit sensitive data. Consider anonymizing personal information before creating dumps.
4. **Selective Collection**: Use `excluded_associations` to prevent collecting unnecessary or sensitive associations.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/real_data_tests. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/real_data_tests/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Real Data Tests project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/real_data_tests/blob/main/CODE_OF_CONDUCT.md).