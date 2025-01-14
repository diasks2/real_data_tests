## [Unreleased]

## [0.3.4] - 2025-01-14
### Added
- Alternative native SQL loading method for CI environments
  - Added `load_real_test_data_native` method that doesn't rely on system commands
  - Works in restricted environments like GitHub Actions
  - Uses ActiveRecord's native connection for SQL execution
  - Maintains same transaction and foreign key handling behavior

## [0.3.3] - 2025-01-14
### Fixed
- Improved circular dependency handling in PgDumpGenerator for self-referential associations
  - Added robust checks for self-referential associations during topological sort
  - Updated dependency graph building to properly exclude prevented circular dependencies
  - Fixed model name handling in circular dependency error messages
  - Improved error reporting for circular dependency detection
- Enhanced PresetConfiguration circular dependency prevention
  - Added more reliable tracking of prevented reciprocal associations using Sets
  - Improved handling of both class and string model names in prevention checks
  - Better support for multiple prevented dependencies per model
- Updated record collection depth handling
  - Fixed max depth enforcement for nested associations
  - Added proper depth tracking for self-referential relationships
  - Improved interaction between max depth and circular dependency prevention

## [0.3.2] - 2025-01-14
### Fixed
- Enhanced association statistics tracking in RecordCollector
  - Added separate statistics tracking method to ensure accurate counts
  - Stats are now tracked before circular dependency checks
  - Fixed parent-child relationship counting in recursive associations
  - Improved initialization of statistics structures for better reliability

## [0.3.1] - 2025-01-14
### Fixed
- Fixed circular dependency handling in RecordCollector to correctly limit record collection
  - Moved prevention logic earlier in the collection process to stop circular dependencies before record collection
  - Improved tracking of visited associations for more accurate prevention
  - Added better logging for dependency prevention decisions
  - Fixed test case for circular dependency prevention in nested associations

## [0.3.0] - 2025-01-13
### Added
- **Polymorphic Association Support**:
  - RecordCollector now supports tracking and collecting records from polymorphic associations.
  - Polymorphic `belongs_to`, `has_many`, and `has_one` associations are automatically detected and processed during data collection.
  - Added tracking for polymorphic types in `@collection_stats` to provide detailed insights into polymorphic relationships.
  - Graceful handling of missing records in polymorphic associations using error logging.

### Fixed
- Improved error handling for `ActiveRecord::RecordNotFound` exceptions when loading polymorphic associations.
- Correctly initializes and updates association statistics for polymorphic associations in `@collection_stats`.

## [0.2.1] - 2025-01-13
### Fixed
- Fixed JSONB field handling to output '{}' instead of empty string for blank values
- Added test coverage for JSONB field handling in PgDumpGenerator

## [0.2.0] - 2025-01-13
### Added
- New preset system for managing different test data configurations
- Added `preset`, `use_preset`, and `with_preset` methods for configuration
- Support for multiple named configuration presets
- Added documentation for using presets
- New PresetConfig class to handle preset-specific configurations

### Changed
- Refactored Configuration class to use preset-based approach
- Moved configuration methods into PresetConfig class
- Updated documentation with preset usage examples and best practices

## [0.1.0] - 2025-01-11
- Initial release