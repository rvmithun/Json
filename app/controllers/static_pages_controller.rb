#!/usr/bin/env ruby
require 'thor'
require 'mustache'
require_relative '../lib/json_resume'
require 'archive/tar/minitar'
include Archive::Tar
require 'zlib'
require 'pdfkit'
require 'rest-client'

WL_URL = "https://www.writelatex.com/docs"
class StaticPagesController < ApplicationController
  def home

  end
  #desc "convert /path/to/json/file", "converts the json to pretty resume format"
  #option :out, :default=>"html", :banner=>"output_type", :desc=>"html|html_pdf|tex|tex_pdf|md"
  #option :template, :banner=>"template_path", :desc=>"path to customized template (optional)"
  def convert(json_input)
    puts "Generating the #{options[:out]} type..."
    puts send('convert_to_'+options[:out], json_input, get_template(options))
  end

  #desc "sample", "Generates a sample json file in cwd"
  def sample()
    cwd = Dir.pwd
    json_file_paths = Dir["#{@@orig_locn}/../examples/*.json"]
    json_file_names = json_file_paths.map{|x| File.basename(x)}
    FileUtils.cp json_file_paths, Dir.pwd
    msg = "Generated #{json_file_names.join(" ")} in #{cwd}/"
    msg += "\nYou can now modify it and call: json_resume convert <file.json>"
    puts msg
  end

  #no_commands do
   # @@orig_locn = File.expand_path(File.dirname(__FILE__))

    def get_template(options)
      out_type = options[:out].split('_').first #html for both html, html_pdf
      options[:template] || "#{@@orig_locn}/../templates/default_#{out_type}.mustache"
    end

    def convert_to_html(json_input, template, dest=Dir.pwd, dir_name='resume')
      tgz = Zlib::GzipReader.new(File.open("#{@@orig_locn}/../extras/resume_html.tar.gz", 'rb'))
      Minitar.unpack(tgz, "#{dest}/#{dir_name}")
      msg = generate_file(json_input, template, "html", "#{dest}/#{dir_name}/page.html")
      msg += "\nPlace #{dest}/#{dir_name}/ in /var/www/ to host."
    end

    def convert_to_html_pdf(json_input, template, dest=Dir.pwd)
      tmp_dir = ".tmp_resume"
      convert_to_html(json_input, template, dest, tmp_dir)
      PDFKit.configure do |config|
        config.default_options = {
            :footer_right => "Page [page] of [toPage]    .\n",
            :footer_font_size => 10,
            :footer_font_name => "Georgia"
        }
      end
      html_file = File.new("#{dest}/#{tmp_dir}/core-page.html")

      pdf_options = {
          :margin_top => 2.0,
          :margin_left=> 0.0,
          :margin_right => 0.0,
          :margin_bottom => 4.0,
          :page_size => 'Letter'
      }
      kit = PDFKit.new(html_file, pdf_options)

      kit.to_file(dest+"/resume.pdf")
      FileUtils.rm_rf "#{dest}/#{tmp_dir}"
      msg = "\nGenerated resume.pdf at #{dest}."
    end

    def convert_to_tex(json_input, template, dest=Dir.pwd, filename="resume.tex")
      generate_file(json_input, template, "latex", "#{dest}/#{filename}")
    end

    def convert_to_tex_pdf(json_input, template, dest=Dir.pwd)
      file1 = "resume"; filename = "#{file1}.tex"
      convert_to_tex(json_input, template, dest, filename)
      if `which pdflatex` == ""
        puts "It looks like pdflatex is not installed..."
        puts "Either install it with instructions at..."
        puts "http://dods.ipsl.jussieu.fr/fast/pdflatex_install.html"
        return use_write_latex(dest, filename)
      end
      if `kpsewhich moderncv.cls` == ""
        puts "It looks liks moderncv package for tex is not installed"
        puts "Read about it here: http://ctan.org/pkg/moderncv"
        return use_write_latex(dest, filename)
      end
      system("pdflatex -shell-escape -interaction=nonstopmode #{dest}/#{filename}")
      [".tex",".out",".aux",".log"].each do |ext|
        FileUtils.rm "#{dest}/#{file1}#{ext}"
      end
      msg = "\nPDF is ready at #{dest}/#{file1}.pdf"
    end

    def use_write_latex(dest, filename)
      reply = ask "Create PDF online using writeLatex ([y]n)?"
      if reply == "" || reply == "y"
        return convert_using_writeLatex(dest, filename)
      end
      msg = "Latex file created at #{dest}/#{filename}"
    end

    def convert_using_writeLatex(dest, filename)
      tex_file = File.read("#{dest}/#{filename}")
      RestClient.post(WL_URL, :snip => tex_file, :splash => "none") do |response, req, res, &bb|
        FileUtils.rm "#{dest}/#{filename}"
        msg = "\nPDF is ready at #{response.headers[:location]}"
      end
    end

    def convert_to_md(json_input, template, dest=Dir.pwd)
      generate_file(json_input, template, "markdown", "#{dest}/resume.md")
    end

    def generate_file(json_input, template, output_type, dest)
      resume_obj = JsonResume.new(json_input, "output_type" => output_type)
      mustache_obj  = Mustache.render(File.read(template), resume_obj.reader.hash)
      File.open(dest,'w') {|f| f.write(mustache_obj) }
      return "\nGenerated files present at #{dest}"
    end

  end






