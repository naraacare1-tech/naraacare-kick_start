# One-time iOS flavor setup (doc 08 §4). Run on a Mac from the repo root:
#
#   gem install xcodeproj -v 1.27.0
#   ruby tool/ios/setup_flavors.rb
#   cd ios && pod install
#
# Creates build configurations Debug-<flavor>, Release-<flavor>, Profile-<flavor> for
# dev/staging/prod, points the Runner target at ios/Flutter/flavors/<config>.xcconfig
# (bundle ID + display name), and creates shared schemes named dev, staging and prod,
# matching `flutter run --flavor <flavor>`. Safe to re-run (idempotent).
#
# After running: add to ios/Podfile, below `project 'Runner', {`:
#   'Debug-dev' => :debug, 'Profile-dev' => :release, 'Release-dev' => :release,
#   'Debug-staging' => :debug, 'Profile-staging' => :release, 'Release-staging' => :release,
#   'Debug-prod' => :debug, 'Profile-prod' => :release, 'Release-prod' => :release,

require 'xcodeproj'

FLAVORS = %w[dev staging prod].freeze
BUILD_TYPES = { 'Debug' => :debug, 'Release' => :release, 'Profile' => :release }.freeze

project_path = File.expand_path('../../ios/Runner.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)
runner = project.targets.find { |t| t.name == 'Runner' } or abort('Runner target not found')
tests = project.targets.find { |t| t.name == 'RunnerTests' }
flutter_group = project.main_group.find_subpath('Flutter', false) or abort('Flutter group not found')

def clone_config(owner, base_name, new_name, kind)
  existing = owner.build_configurations.find { |c| c.name == new_name }
  return existing if existing

  base = owner.build_configurations.find { |c| c.name == base_name } or abort("#{base_name} missing")
  config = owner.add_build_configuration(new_name, kind)
  config.build_settings = Marshal.load(Marshal.dump(base.build_settings))
  config
end

FLAVORS.each do |flavor|
  BUILD_TYPES.each do |type, kind|
    name = "#{type}-#{flavor}"
    xcconfig = "flavors/#{name}.xcconfig"
    file_ref = flutter_group.files.find { |f| f.path == xcconfig } || flutter_group.new_file(xcconfig)

    clone_config(project, type, name, kind)

    runner_config = clone_config(runner, type, name, kind)
    runner_config.base_configuration_reference = file_ref
    # Bundle ID must come from the flavor xcconfig, not a target-level override.
    runner_config.build_settings.delete('PRODUCT_BUNDLE_IDENTIFIER')

    clone_config(tests, type, name, kind) if tests
  end

  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(runner)
  scheme.set_launch_target(runner)
  scheme.add_test_target(tests) if tests
  scheme.launch_action.build_configuration = "Debug-#{flavor}"
  scheme.test_action.build_configuration = "Debug-#{flavor}"
  scheme.analyze_action.build_configuration = "Debug-#{flavor}"
  scheme.profile_action.build_configuration = "Profile-#{flavor}"
  scheme.archive_action.build_configuration = "Release-#{flavor}"
  scheme.save_as(project_path, flavor, true)
end

project.save
puts 'iOS flavors configured: dev, staging, prod. Now update ios/Podfile and run `pod install`.'
