# Real Data Tests

Create realistic test data in your Rails applications by extracting real records and their associations from your PostgreSQL database.

> **Note**: This gem currently only supports PostgreSQL databases. MySQL and other database adapters are not supported.

## Why use Real Data Tests?

Testing with realistic data is crucial for catching edge cases and ensuring your application works with real-world data structures. However, creating complex test fixtures that accurately represent your data relationships can be time-consuming and error-prone.

Real Data Tests solves this by:
- Automatically analyzing and extracting real records and their associations
- Creating reusable SQL dumps that can be committed to your repository
- Making it easy to load realistic test data in your specs
- Supporting data anonymization for sensitive information

## Requirements

- Rails 5.0 or higher
- PostgreSQL database
- `pg_dump` command-line utility installed and accessible
- Database user needs sufficient permissions to run `pg_dump`

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
Rails.application.config.after_initialize do
  RealDataTests.configure do |config|
    # Directory where SQL dumps will be stored
    config.dump_path = 'spec/fixtures/real_data_dumps'

    # Define a preset for collecting patient visit data
    config.preset :patient_visits do |p|
      p.include_associations(
        :visit_note_type,
        :patient_status
      )

      p.include_associations_for 'Patient',
        :visit_notes,
        :treatment_reports

      p.prevent_reciprocal 'VisitNoteType.visit_notes'

      p.anonymize 'Patient', {
        first_name: -> (_) { Faker::Name.first_name },
        last_name:  -> (_) { Faker::Name.last_name }
      }
    end

    # Define a preset for organization structure
    config.preset :org_structure do |p|
      p.include_associations(
        :organization,
        :user
      )

      p.include_associations_for 'Department',
        :employees,
        :managers

      p.limit_association 'Department.employees', 100

      p.anonymize 'User', {
        email: -> (user) { Faker::Internet.email(name: "user#{user.id}") }
      }
    end
  end
end
```

## Using Presets

Real Data Tests allows you to define multiple configuration presets for different data extraction needs. This is particularly useful when you need different association rules and anonymization settings for different testing scenarios.

### Defining Presets

You can define presets in your configuration:

```ruby
RealDataTests.configure do |config|
  # Define a preset for patient data
  config.preset :patient_data do |p|
    p.include_associations(:patient_status, :visit_note_type)
    p.include_associations_for 'Patient', :visit_notes
    p.limit_association 'Patient.visit_notes', 10
  end

  # Define another preset for billing data
  config.preset :billing_data do |p|
    p.include_associations(:payment_method, :insurance_provider)
    p.include_associations_for 'Invoice', :line_items, :payments
    p.anonymize 'PaymentMethod', {
      account_number: -> (_) { Faker::Finance.credit_card }
    }
  end
end
```

### Using Presets in Your Code

You can use presets in several ways:

```ruby
# Create dump file using a specific preset
RealDataTests.with_preset(:patient_data) do
  RealDataTests.create_dump_file(patient, name: "patient_with_visits")
end

# Switch to a different preset
RealDataTests.use_preset(:billing_data)
RealDataTests.create_dump_file(invoice, name: "invoice_with_payments")

# Use in tests
RSpec.describe "Patient Visits" do
  it "loads visit data correctly" do
    RealDataTests.with_preset(:patient_data) do
      load_real_test_data("patient_with_visits")
      # Your test code here
    end
  end
end
```

### Benefits of Using Presets

- **Organized Configuration**: Keep related association rules and anonymization settings together
- **Reusability**: Define configurations once and reuse them across different tests
- **Clarity**: Make it clear what data is being extracted for each testing scenario
- **Flexibility**: Easily switch between different data extraction rules
- **Maintainability**: Update all related settings in one place

### Best Practices for Presets

1. **Descriptive Names**: Use clear, purpose-indicating names for your presets
2. **Single Responsibility**: Each preset should focus on a specific testing scenario
3. **Documentation**: Comment your presets to explain their purpose and usage
4. **Composition**: Group related models and their associations in the same preset
5. **Version Control**: Keep preset definitions with your test code for easy reference

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
2. Collect all associated records based on your configuration
3. Apply any configured anonymization rules
4. Generate a SQL dump file in your configured dump_path

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

## Association Control

Real Data Tests provides several ways to control how associations are collected and loaded.

### Global Association Filtering

You can control which associations are collected globally using either whitelist or blacklist mode:

```ruby
# Whitelist Mode - ONLY collect these associations
config.include_associations(
  :user,
  :organization,
  :profile
)

# OR Blacklist Mode - collect all EXCEPT these associations
config.exclude_associations(
  :very_large_association,
  :unused_association
)
```

### Model-Specific Associations

For more granular control, you can specify which associations should be collected for specific models:

```ruby
RealDataTests.configure do |config|
  # Global associations that apply to all models
  config.include_associations(
    :organization,
    :user
  )

  # Model-specific associations
  config.include_associations_for 'Patient',
    :visit_notes,
    :treatment_reports,
    :patient_status

  config.include_associations_for 'Discipline',
    :organization,  # Will collect this even though it's in global associations
    :credentials,
    :specialty_types
end
```

This is particularly useful when:
- Different models need different association rules
- The same association name means different things on different models
- You want to collect an association from one model but not another
- You need to maintain a clean separation of concerns in your test data

### Association Loading Control

You can further refine how associations are loaded using limits and reciprocal prevention:

```ruby
RealDataTests.configure do |config|
  # Limit the number of records loaded for specific associations
  config.limit_association 'Patient.visit_notes', 10

  # Prevent loading associations in the reverse direction
  config.prevent_reciprocal 'VisitNoteType.visit_notes'
end
```

### Best Practices for Association Control

1. **Start with Global Rules**: Define global association rules that apply to most models
2. **Add Model-Specific Rules**: Use `include_associations_for` when you need different rules for specific models
3. **Control Data Volume**: Use `limit_association` for has_many relationships that could return large numbers of records
4. **Prevent Cycles**: Use `prevent_reciprocal` to break circular references in your association chain
5. **Monitor Performance**: Watch the size of your dump files and adjust your association rules as needed

## Association Filtering

Real Data Tests provides two mutually exclusive approaches to control which associations are collected:

### Whitelist Mode
Use this when you want to ONLY collect specific associations:
```ruby
RealDataTests.configure do |config|
  config.include_associations(
    :user,
    :profile,
    :posts,
    :comments
  )
end
```

### Blacklist Mode
Use this when you want to collect all associations EXCEPT specific ones:
```ruby
RealDataTests.configure do |config|
  config.exclude_associations(
    :large_association,
    :unused_association
  )
end
```

> **Note**: You must choose either blacklist or whitelist mode, not both. Attempting to use both will raise an error.

## Data Anonymization

Real Data Tests uses lambdas with the Faker gem for flexible data anonymization. Each anonymization rule receives the record as an argument, allowing for dynamic value generation:

```ruby
RealDataTests.configure do |config|
  config.anonymize 'User', {
    # Simple value replacement
    first_name: -> (_) { Faker::Name.first_name },

    # Dynamic value based on record
    email: -> (user) { Faker::Internet.email(name: "user#{user.id}") },

    # Custom anonymization logic
    full_name: -> (user) {
      "#{Faker::Name.first_name} #{Faker::Name.last_name}"
    }
  }
end
```

### Common Faker Examples

```ruby
{
  name:         -> (_) { Faker::Name.name },
  username:     -> (_) { Faker::Internet.username },
  email:        -> (_) { Faker::Internet.email },
  phone:        -> (_) { Faker::PhoneNumber.phone_number },
  address:      -> (_) { Faker::Address.street_address },
  company:      -> (_) { Faker::Company.name },
  description:  -> (_) { Faker::Lorem.paragraph }
}
```

See the [Faker documentation](https://github.com/faker-ruby/faker) for a complete list of available generators.

## Database Cleaner Integration

If you're using DatabaseCleaner with models that have foreign key constraints, you'll need to handle the cleanup order carefully.

### Disable Foreign Key Constraints During Cleanup
Add this to your DatabaseCleaner configuration:

```ruby
config.append_after(:suite) do
  # Disable foreign key constraints
  ActiveRecord::Base.connection.execute('SET session_replication_role = replica;')
  begin
    # Your cleanup code here
    SKIP_MODELS.each { |model| model.delete_all }
  ensure
    # Re-enable foreign key constraints
    ActiveRecord::Base.connection.execute('SET session_replication_role = DEFAULT;')
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
3. **Data Privacy**: Always use anonymization for sensitive data before creating dumps.
4. **Association Control**: Use association filtering to keep dumps focused and maintainable.
5. **Unique Identifiers**: Use record IDs in anonymized data to maintain uniqueness (e.g., emails).

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/diasks2/real_data_tests. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/diasks2/real_data_tests/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Real Data Tests project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/diasks2/real_data_tests/blob/main/CODE_OF_CONDUCT.md).