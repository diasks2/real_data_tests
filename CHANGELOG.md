## [Unreleased]

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