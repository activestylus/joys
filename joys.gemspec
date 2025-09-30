# frozen_string_literal: true

require_relative "lib/joys/version"

Gem::Specification.new do |spec|
  spec.name = "joys"
  spec.version = Joys::VERSION
  spec.authors = ["Steven Garcia"]
  spec.email = ["stevendgarcia@gmail.com"]

  spec.summary = "Pure Ruby Templating Engine on Steroids. Ludicrous Speed. Zero Dependencies"
  spec.description = "Joys brings proper UI components to Rubyland, with co-located and deduped styling in components, pages and layouts. The robust features are complimented by a strong performance profile that outpaces most ruby templating solutions"
  spec.homepage = "https://github.com/activestylus/joys.git"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.3"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/activestylus/joys.git"
  spec.metadata["changelog_uri"] = "https://github.com/activestylus/joys/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
