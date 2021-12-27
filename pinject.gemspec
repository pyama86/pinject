# frozen_string_literal: true

require_relative 'lib/pinject/version'

Gem::Specification.new do |spec|
  spec.name = 'pinject'
  spec.version = Pinject::VERSION
  spec.authors = ['pyama']
  spec.email = ['pyama@pepabo.com']

  spec.summary = 'inject package update commands to your docker images'
  spec.description = 'detect os your docker image and update os pakaces.'
  spec.homepage = 'https://github.com/pyama86/pinject'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 2.6.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/pyama86/pinject'
  spec.metadata['changelog_uri'] = 'https://github.com/pyama86/pinject/CHANGELOG.md'

  spec.files = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']
  spec.add_dependency 'docker-api'
end
