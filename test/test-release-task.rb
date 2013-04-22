# -*- coding: utf-8 -*-
#
# Copyright (C) 2013 Haruka Yoshihara <yoshihara@clear-code.com>
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
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

require "test/unit/rr"
require "tmpdir"

class ReleaseTaskTest < Test::Unit::TestCase
  def teardown
    Rake::Task.clear
  end

  def test_info_update
    Dir.mktmpdir do |base_dir|
      index_dir = File.join(base_dir, "index_dir")

      spec = Gem::Specification.new
      Packnga::ReleaseTask.new(spec) do |task|
        task.index_html_dir = index_dir
        task.base_dir = base_dir
      end

      index = "1-0-0 2013-03-28"
      FileUtils.mkdir_p(index_dir)
      index_file = File.join(index_dir, "index.html")
      File.open(index_file, "w") do |file|
        file.print(index)
      end

      ja_index_dir = File.join(index_dir, "ja")
      FileUtils.mkdir_p(ja_index_dir)
      ja_index_file = File.join(ja_index_dir, "index.html")
      File.open(ja_index_file, "w") do |file|
        file.print(index)
      end

      ENV["OLD_VERSION"] = "1.0.0"
      ENV["VERSION"]     = "1.0.1"
      ENV["OLD_RELEASE_DATE"] = "2013-03-28"
      ENV["RELEASE_DATE"]     = "2013-04-01"
      Rake::Task["release:info:update"].invoke

      expected_index = "1-0-1 2013-04-01"
      assert_equal(expected_index, File.read(index_file))
      assert_equal(expected_index, File.read(ja_index_file))
    end
  end

  def test_upload_references
    Dir.mktmpdir do |base_dir|
      package_name = "packnga"
      index_dir = File.join(base_dir, "index_dir")
      reference_dir = File.join(base_dir, "html", package_name)
      reference_filename = "file.html"

      spec = Gem::Specification.new do |_spec|
        _spec.name = package_name
      end

      Packnga::ReleaseTask.new(spec) do |task|
        task.index_html_dir = index_dir
        task.base_dir = base_dir
      end

      FileUtils.mkdir_p(reference_dir)
      FileUtils.touch(File.join(reference_dir, reference_filename))

      Rake::Task["release:references:upload"].invoke
      uploaded_path = File.join(index_dir, reference_filename)
      assert_true(File.exist?(uploaded_path))
    end
  end
end
