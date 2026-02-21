require_relative "lib/maquina_generators/version"

Gem::Specification.new do |spec|
  spec.name = "maquina_generators"
  spec.version = MaquinaGenerators::VERSION
  spec.authors = ["Mario Alberto Chavez"]
  spec.email = ["mario.chavez@gmail.com"]

  spec.summary = "Rails generators from the Maquina umbrella"
  spec.description = "A collection of Rails generators: clave (passwordless auth), and more to come."
  spec.homepage = "https://github.com/maquina-app/maquina_generators"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir.chdir(__dir__) do
    Dir["{lib,test}/**/*", "LICENSE.txt", "README.md", "Rakefile"]
  end

  spec.require_paths = ["lib"]

  spec.add_development_dependency "rails", ">= 7.2"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
