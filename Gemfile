#since war/jar bundle requires gem package; use gem-in-a-box for testing
#or execute tabula via "rackup".
#source "http://127.0.0.1:9292"

source "https://rubygems.org"
ruby '1.9.3', engine: 'jruby', engine_version: '1.7.3'

platform :jruby do
  gem "cuba"
  gem "rack"
  gem "tilt"
  gem "docsplit"
  gem "mizuno"
  gem "mini_magick"
  gem "tabula-extractor",github: "jazzido/tabula-extractor", :require => "tabula"
  gem 'rtesseract', github: "mimosz/rtesseract"
 # gem "tabula-extractor", '>=0.6.4', :require => "tabula"

  group :development do
    gem "rake"
    gem "warbler"
  end
end
