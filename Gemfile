#since war/jar bundle requires gem package; use gem-in-a-box for testing
#or execute tabula via "rackup".
#source "http://127.0.0.1:9292"

source "https://rubygems.org"
ruby '1.9.3', engine: 'jruby', engine_version: '1.7.1'

platform :jruby do
  gem "cuba"
  gem "rack"
  gem "tilt"
  gem "tabula-extractor",github: "jazzido/tabula-extractor", :require => "tabula"
  gem "pdf_extract",github: "noahpryor/pdf_extract"

 # gem "tabula-extractor", '>=0.6.4', :require => "tabula"

  group :development do
    gem "rake"
    gem "warbler"
  end
end
