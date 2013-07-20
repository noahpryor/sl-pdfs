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
  gem "slogger"
  gem "mini_magick"
  gem "tabula-extractor",github: "jazzido/tabula-extractor", :require => "tabula"
#  gem "tesseract_bin", "~> 1.0.2"
 # gem 'tesseract-ocr'
 gem "rtesseract", github: "mimosz/rtesseract"
 # gem "tabula-extractor", '>=0.6.4', :require => "tabula"
 gem "rake"
 gem "warbler"
 gem 'rack-cors', :require => 'rack/cors'
  group :development do
    gem "warbler"
  end
end
