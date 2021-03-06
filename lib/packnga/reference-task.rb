# -*- coding: utf-8 -*-
#
# Copyright (C) 2011-2013  Haruka Yoshihara <yoshihara@clear-code.com>
# Copyright (C) 2012-2013  Kouhei Sutou <kou@clear-code.com>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License version 2.1 as published by the Free Software Foundation.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

require "erb"
require "gettext/tools"
require "gettext/tools/task"
require "tempfile"
require "tmpdir"
require "rake/clean"

module Packnga
  # This class creates reference tasks.
  # They generate, translate and prepare to publish references.
  #
  # @since 0.9.0
  class ReferenceTask
    include Rake::DSL
    include ERB::Util

    # This attribute is used to set path of base directory of document.
    # @return [String] path of base directory of document
    attr_accessor :base_dir

    # This attribute is used to set README file.
    # @return [String] path of readme file
    attr_accessor :readme

    # This attribute is used to set source files for document.
    # @return [Array<String>] target source files
    attr_accessor :source_files

    # This attribute is used to set text files for document.
    # @return [Array<String>] target text files
    attr_accessor :text_files

    # This attribute is used to set the language you wrote original
    # document. Its default value is "en" (English).
    # @return [String] language you used to write document
    #
    # @see DocumentTask#original_language=
    #
    # @since 0.9.6
    attr_accessor :original_language

    # This attribute is used to set languages for translated document.
    # If original_language isn't English, its default value is one.
    # Otherwise, it is not specified.
    #
    # @see DocumentTask#translate_languages=
    #   See this page to specifiy multiple languages to this attribute.
    # @see DocumentTask#translate_language=
    #   See this page to specifiy a single language to this attribute.
    # @return [Array<String>] target languages
    #
    # @since 0.9.6
    attr_accessor :translate_languages

    # @private
    def initialize(spec)
      @spec = spec
      @base_dir = nil
      @original_language = nil
      @translate_languages = nil
      @supported_languages = nil
      @source_files = nil
      @text_files = nil
      @readme = nil
      @extra_files = nil
      @files = nil
      @po_dir = nil
    end

    # @private
    def define
      set_default_values
      define_tasks
    end

    private
    def set_default_values
      @base_dir ||= Pathname.new("doc")
      @original_language ||= "en"
      if @original_language == "en"
        @translate_languages ||= []
      else
        @translate_languages ||= ["en"]
      end
      @supported_languages = [@original_language, *@translate_languages]
      @po_dir = "#{@base_dir}/po"
      @extra_files = @text_files
      @extra_files += [@readme] if @readme
      @files = @source_files + @extra_files
    end

    def reference_base_dir
      @base_dir + "reference"
    end

    def html_base_dir
      @base_dir + "html"
    end

    def html_reference_dir
      html_base_dir + @spec.name
    end

    def define_tasks
      namespace :reference do
        define_gettext_tasks
        define_pot_tasks
        define_po_tasks
        define_translate_task
        define_generate_task
        define_publication_task
      end
      task html_reference_dir.to_s => "reference:publication:generate"
    end

    def define_gettext_tasks
      return if @files.empty?

      GetText::Tools::Task.define do |task|
        task.spec = @spec
        task.locales = @translate_languages
        task.po_base_directory = @po_dir
        task.files = @files
        task.enable_description = false
        task.pot_creator = lambda do |pot_file_path|
          create_pot_file(pot_file_path.to_s)
        end
      end
    end

    def create_pot_file(pot_file_path)
      options = ["-o", pot_file_path]
      options += @source_files
      options += ["-"]
      options += @extra_files
      YARD::CLI::I18n.run(*options)
    end

    def define_pot_tasks
      namespace :pot do
        desc "Generates POT file."
        task :generate => "gettext:pot:create"
      end
    end

    def define_po_tasks
      yard_po_files = []

      @translate_languages.each do |language|
        po_file = "#{@po_dir}/#{language}/#{@spec.name}.po"
        yard_po_file = "#{@po_dir}/#{language}.po"
        yard_po_files << yard_po_file
        namespace :po do
          namespace language do
            task :prepare do
              if File.exist?(yard_po_file)
                mkdir_p(File.dirname(po_file))
                mv(yard_po_file, po_file)
              end
            end
          end
        end
        file yard_po_file => ["po:#{language}:prepare", po_file] do
          cp(po_file, yard_po_file)
        end
      end

      namespace :po do
        desc "Updates PO files."
        task :update => yard_po_files
      end
    end

    def define_translate_task
      directory reference_base_dir.to_s
      namespace :translate do
        @translate_languages.each do |language|
          po_file = "#{@po_dir}/#{language}.po"
          desc "Translates documents to #{language}."
          task language => [po_file, reference_base_dir, *@files] do
            translate_doc_dir = "#{reference_base_dir}/#{language}"
            rm_rf(translate_doc_dir)
            yardoc = YARD::CLI::Yardoc.new
            options = [
              "--title", @spec.name,
              "--po-dir", @po_dir,
              "--locale", language,
              "--charset", "utf-8",
              "--no-private",
              "--output-dir", translate_doc_dir
            ]
            options += ["--readme", @readme] if @readme
            options += @source_files
            options += ["-"]
            options += @text_files
            yardoc.run(*options)
          end
        end
      end

      translate_task_names = @translate_languages.collect do |language|
        "reference:translate:#{language}"
      end
      desc "Translates references."
      task :translate => translate_task_names
    end

    def define_generate_task
      desc "Generates references."
      task :generate => [:yard, :translate]
    end

    def define_publication_task
      namespace :publication do
        task :prepare do
          @supported_languages.each do |language|
            raw_reference_dir = reference_base_dir + language.to_s
            prepared_reference_dir = html_reference_dir + language.to_s
            rm_rf(prepared_reference_dir.to_s)
            raw_reference_dir.find do |path|
              relative_path = path.relative_path_from(raw_reference_dir)
              prepared_path = generate_prepared_path(prepared_reference_dir,
                                                     relative_path)
              if path.directory?
                mkdir_p(prepared_path.to_s)
              else
                case path.basename.to_s
                when /(?:file|method|class)_list\.html\z/
                  cp(path.to_s, prepared_path.to_s)
                when /\.html\z/
                  create_published_file(path, relative_path, prepared_path,
                                        language)
                else
                  cp(path.to_s, prepared_path.to_s)
                end
              end
            end
          end
        end

        desc "Generates reference for publication."
        task :generate => ["reference:generate",
                           "reference:publication:prepare"]
      end
    end

    def create_published_file(path, relative_path, prepared_path, language)
      relative_dir_path = relative_path.dirname
      if path.basename.to_s == "_index.html"
        current_path = relative_dir_path + "alphabetical_index.html"
      else
        current_path = relative_dir_path + path.basename
        if current_path.basename.to_s == "index.html"
          current_path = current_path.dirname
        end
      end
      top_path = html_base_dir.relative_path_from(prepared_path.dirname)
      package_path = top_path + @spec.name
      paths = {
        :top     => top_path,
        :current => current_path,
        :package => package_path,
      }
      templates = {
        :head   => erb_template("head.#{language}"),
        :header => erb_template("header.#{language}"),
        :footer => erb_template("footer.#{language}")
      }
      content = apply_templates(File.read(path.to_s),
                                paths,
                                templates,
                                language)
      content = content.gsub(/"(.*?)_index\.html"/,
                             "\"\\1alphabetical_index.html\"")
      File.open(prepared_path.to_s, "w") do |file|
        file.print(content)
      end
    end

    def generate_prepared_path(prepared_reference_dir, relative_path)
      prepared_path = prepared_reference_dir + relative_path
      if prepared_path.basename.to_s == "_index.html"
        prepared_path.dirname + "alphabetical_index.html"
      else
        prepared_path
      end
    end

    def apply_templates(content, paths, templates, language)
      content = content.gsub(/lang="en"/, "lang=\"#{language}\"")

      title = nil
      content = content.gsub(/<title>(.+?)<\/title>/m) do |matched_text|
        title = $1
        head_template = templates[:head]
        if head_template
          head_template.result(binding)
        else
          matched_text
        end
      end

      header_template = templates[:header]
      if header_template
        content = content.gsub(/<div id="main".*?>/) do |main_div_start|
          "#{main_div_start}\n#{header_template.result(binding)}\n"
        end
      end

      footer_template = templates[:footer]
      if footer_template
        content = content.gsub(/<\/div>\s*<\/body/m) do |main_div_end|
          "\n#{footer_template.result(binding)}\n#{main_div_end}"
        end
      end

      content
    end

    def erb_template(name)
      file = File.join("doc/templates", "#{name}.html.erb")
      return nil unless File.exist?(file)
      template = File.read(file)
      erb = ERB.new(template, nil, "-")
      erb.filename = file
      erb
    end
  end
end
