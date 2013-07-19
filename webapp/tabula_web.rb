# -*- coding: utf-8 -*-
require 'cuba'
require 'cuba/render'
require 'digest/sha1'
require 'json'
require 'csv'
require 'tempfile'
require 'fileutils'
require 'mini_magick'
require 'tesseract'
require 'tabula' # tabula-extractor gem
#require 'pdf_extract'
require 'slogger'
require_relative './tabula_settings.rb'

unless File.directory?(TabulaSettings::DOCUMENTS_BASEPATH)
  raise "DOCUMENTS_BASEPATH does not exist or is not a directory."
end

require_relative '../lib/tabula_job_executor/executor.rb'
require_relative '../lib/tabula_job_executor/jobs/generate_document_metadata.rb'
require_relative '../lib/tabula_job_executor/jobs/generate_thumbnails.rb'
require_relative '../lib/tabula_job_executor/jobs/generate_page_index.rb'
require_relative '../lib/tabula_job_executor/jobs/detect_tables.rb'


def is_valid_pdf?(path)
  File.open(path, 'r') { |f| f.read(4) } == '%PDF'
end


STATIC_ROOT = defined?($servlet_context) ? \
                File.join($servlet_context.getRealPath('/'), 'WEB-INF/webapp/static') : \
                File.join(File.dirname(__FILE__), 'static')
slogger = Slogger::Logger.new "sample_app", :debug, :local0

Cuba.plugin Cuba::Render
Cuba.settings[:render].store(:views, File.expand_path("views", File.dirname(__FILE__)))
Cuba.use Rack::MethodOverride
Cuba.use Rack::Static, root: STATIC_ROOT, urls: ["/css","/js", "/img", "/swf"]
Cuba.use Rack::ContentLength
Cuba.use Rack::Reloader
Cuba.use Slogger::Rack::RequestLogger, slogger
Cuba.define do

  if TabulaSettings::ENABLE_DEBUG_METHODS
    require_relative './tabula_debug.rb'
    on 'debug' do
      run TabulaDebug
    end
  end


  on 'queue' do
    require_relative './tabula_job_progress.rb'
    run TabulaJobProgress
  end

  on delete do

    on 'pdf/:file_id/page/:page_number' do |file_id, page_number|
      index_fname = File.join(TabulaSettings::DOCUMENTS_BASEPATH,
                              file_id,
                              'pages.json')
      index = File.open(index_fname) { |f| JSON.load(f) }
      index.find { |p| p['number'] == page_number.to_i }['deleted'] = true
      File.open(index_fname, 'w') { |f| f.write JSON.generate(index) }
    end

    # delete an uploaded file
    on 'pdf/:file_id' do |file_id|
      workspace_file = File.join(TabulaSettings::DOCUMENTS_BASEPATH, 'workspace.json')
      raise if !File.exists?(workspace_file)

      workspace = File.open(workspace_file) { |f| JSON.load(f) }
      f = workspace.find { |g| g['id'] == file_id }

      FileUtils.rm_rf(File.join(TabulaSettings::DOCUMENTS_BASEPATH, f['id']))
      workspace.delete(f)

      # update safely
      tmp = Tempfile.new('workspace')
      tmp.write(JSON.generate(workspace))
      tmp.flush; tmp.close
      FileUtils.cp(tmp.path, workspace_file)
      tmp.unlink

    end

  end

  on put do
    on 'pdf/:file_id/page/:page_number' do |file_id, page_number|
      # nothing yet
    end
  end

  on get do
    on root do
      workspace_file = File.join(TabulaSettings::DOCUMENTS_BASEPATH, 'workspace.json')
      workspace = if File.exists?(workspace_file)
                    File.open(workspace_file) { |f| JSON.load(f) }
                  else
                    []
                  end

      res.write view("index.html",
                     workspace: workspace)
    end


    on 'pdfs' do
      run Rack::File.new(TabulaSettings::DOCUMENTS_BASEPATH)
    end

    on "pdf/:file_id" do |file_id|
      document_dir = File.join(TabulaSettings::DOCUMENTS_BASEPATH, file_id)
      unless File.directory?(document_dir)
        res.status = 404
      else
        res.write view("pdf_view.html",
                       pages: File.open(File.join(document_dir, 'pages.json')) { |f|
                         JSON.parse(f.read)
                       },
                       file_id: file_id)
      end
    end

  end # /get

  on post do
    on 'upload' do

      # Make sure this is a PDF, before doing anything
      unless is_valid_pdf?(req.params['file'][:tempfile].path)
        res.status = 400
        res.write view("upload_error.html",
                       :message => "Sorry, the file you uploaded was not detected as a PDF. You must upload a PDF file. <a href='/'>Please try again</a>.")
        next # halt this handler
      end

      original_filename = req.params['file'][:filename]
      file_id = Digest::SHA1.hexdigest(Time.now.to_s)
      file_path = File.join(TabulaSettings::DOCUMENTS_BASEPATH, file_id)
      FileUtils.mkdir(file_path)
      begin
        FileUtils.mv(req.params['file'][:tempfile].path,
                     File.join(file_path, 'document.pdf'))
      rescue Errno::EACCES # move fails on windows sometimes
        FileUtils.cp_r(req.params['file'][:tempfile].path,
                       File.join(file_path, 'document.pdf'))
        FileUtils.rm_rf(req.params['file'][:tempfile].path)

      end

      file = File.join(file_path, 'document.pdf')

      # fire off background jobs; in different orders if we're doing autodetection

      document_metadata_job = GenerateDocumentMetadataJob.create(:filename => original_filename,
                                                                 :id => file_id)
      if req.params['autodetect-tables']
        STDERR.puts req.params['autodetect-tables']
        detect_tables_job = DetectTablesJob.create(:filename => file,
                                                   :output_dir => file_path)
      else
        detect_tables_job = nil
      end

      page_index_job = GeneratePageIndexJob.create(:file => file,
                                                   :output_dir => file_path)
      upload_id = GenerateThumbnailJob.create(:file_id => file_id,
                                              :file => file,
                                              :page_index_job_uuid => page_index_job,
                                              :detect_tables_job_uuid => detect_tables_job,
                                              :output_dir => file_path,
                                              :thumbnail_sizes => [560,2048])
      res.redirect "/queue/#{upload_id}"
    end
    on "pdf/:file_id/ocr" do |file_id|
      coords = JSON.load(req.params['coords'])
      puts req.params
      pdf_path = File.join(TabulaSettings::DOCUMENTS_BASEPATH, file_id, 'document_2048_1.png')

      url = coords['url'].gsub("560","2048")
     puts url 
      image =  MiniMagick::Image.open(url)
      puts image.class  
      image_path = "test.png"
       image.write(image_path)
        e = Tesseract::Engine.new {|e|
          e.language  = :eng
          e.blacklist = '|'
        }
        text =  e.text_for(image_path).strip 
        puts text
     # puts File.open(image_path).size
   #   begin 
   #     a = RTesseract.new(image_path,processor: 'mini_magick')
   #   rescue 
       # begin 
       #   a = RTesseract.new(image_path)
     #   rescue 
         # a = ""
      #  end
    #  end
  #    puts a.to_s
   #   begin 
     # dimensions = {x: coords["x"], y: coords["y"],height:coords["height"], width: coords["width"] }
      #puts dimensions
     # mix_block = RTesseract::Mixed.new(image_path,{processor: 'mini_magick', areas: [dimensions]})
      #rescue 
     # mix_block = "3"
     # end

  #    text = mix_block.to_s
    #  File.unlink(img.path)
      coords["image_file"] = image_path
      coords["image_text"] = text
      coords["image_path"] = image_path
  #    puts image_path
    #  pdf_path = File.join(TabulaSettings::DOCUMENTS_BASEPATH, file_id, 'document.pdf')
      message = {
        test: "FEafa"
      }
      res['Content-Type'] = 'application/json'
      res.write coords.to_json
    end

    on "pdf/:file_id/data" do |file_id|
      pdf_path = File.join(TabulaSettings::DOCUMENTS_BASEPATH, file_id, 'document.pdf')

      coords = JSON.load(req.params['coords'])
      coords.sort_by!{|coord_set| [ coord_set['page'], [coord_set['y1'], coord_set['y2']].min.to_i / 10, [coord_set['x1'], coord_set['x2']].min ] }

      tables = coords.each_with_index.map do |coord_set, index|
        extractor = Tabula::Extraction::CharacterExtractor.new(pdf_path, [coord_set['page'].to_i])

        Tabula.make_table(extractor.extract.next.get_text([coord_set['y1'].to_f,
                                                                  coord_set['x1'].to_f,
                                                                  coord_set['y2'].to_f,
                                                                  coord_set['x2'].to_f]))
      end

      case req.params['format']
      when 'csv'
        res['Content-Type'] = 'text/csv'
        Tabula::Writers.CSV(tables.flatten(1), res)
      when 'tsv'
        res['Content-Type'] = 'text/tab-separated-values'
        Tabula::Writers.TSV(tables.flatten(1), res)
      else
        res['Content-Type'] = 'application/json'
        Tabula::Writers.JSON(tables.flatten(1), res)
      end

    end
  end
end
