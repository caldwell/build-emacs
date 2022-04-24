#!/usr/bin/env ruby
#  Copyright © 2021 David Caldwell
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

require 'net/http'
require 'tempfile'
require 'digest'

require_relative 'verbose-shell'

class Build
    attr_accessor :source, :archive_name, :name, :version, :extra_configure_args, :extra_make_args, :builddep, :patches

    def initialize(options)
      @source = URI(options[:source])
      @archive_name = File.basename(options[:source])
      @name = options[:name]
      @version = options[:version]
      if !@name || !@version
        m = @archive_name.match(/^([\w-]+)-(\d[\w.-]+)(\.tar.(\w+))$/)
        raise "couldn't parse #{@archive_name}" unless m
        @name, @version = [m[1], m[2]]
      end
      @extra_configure_args = options[:extra_configure_args] || []
      @extra_make_args = options[:extra_make_args] || []
      @builddep = options[:builddep]
      @patches = options[:patches] || []
    end

    def build_dir
      File.join("build", "#{@name}-#{@version}")
    end

    def archive_path
      File.join("archive", @archive_name)
    end


    def clean
      Vsh.rm_rf(build_dir) if File.exist?(build_dir)
    end

    def prep_build_dir
      Vsh.mkdir_p("build") unless File.exist? "build"
      unless File.exist? build_dir
        Vsh.rm_rf "#{build_dir}.unpatched"
        unpack(archive_path, "#{build_dir}.unpatched")
        patches.each {|patch| Vsh.system(*%W"patch -p0 -d #{build_dir}.unpatched -i #{File.expand_path(patch, File.dirname(__FILE__))}") }
        Vsh.mv "#{build_dir}.unpatched", build_dir
      end
    end

    def fetch
      download_url_to_file(archive_path, source) unless File.exist?(archive_path)
    end

    def build(prefix)
      puts "==> Building #{@name}-#{@version}" if Vsh.verbose
      prep_build_dir()
      configure(prefix)
      if needs_make?
        make()
        install()
      end
    end

    def configure(prefix)
      configure_command = [*%W"./configure --prefix=#{File.absolute_path(prefix)}", *extra_configure_args]
      conf_hash = Digest::SHA2.hexdigest(File.read(archive_path)+configure_command.join(' '))
      return if File.exist? "#{build_dir}.configured" and File.read("#{build_dir}.configured") == conf_hash
      Vsh.chdir(build_dir) {
        Vsh.system(*configure_command)
      }
      File.write("#{build_dir}.configured", conf_hash)
    end

    def needs_make?
      Vsh.system_noraise(*%W"make -C #{build_dir} -q", *extra_make_args) != 0
    end

    def make
      Vsh.system(*%W"make -C #{build_dir} -j 4", *extra_make_args)
    end

    def install
      Vsh.system(*%W"make -C #{build_dir} install")
    end

    def download_url_to_file(dest, url)
      puts "Downloading #{url}...\n" if Vsh.verbose
      Vsh.mkdir_p(File.dirname(dest))
      # Shelling out to curl is so gross. But the stupid ruby libs bundled on 10.11 and 10.12 are sslv3 (!!)
      # so they can't actually do anything on the modern web.
      Vsh.system *%W"curl -o #{dest}.downloading -L #{url}"
      File.rename("#{dest}.downloading", dest)
    end

  def unpack(cache, dest)
    Vsh.mkdir_p(File.dirname(dest))
    Dir.mktmpdir(nil, File.dirname(dest)) do |unpackdir|
      Vsh.system *%W"tar xf #{archive_path} -C #{unpackdir}"
      Vsh.rm_rf dest
      toplevel = Dir["#{unpackdir}/*"]
      if toplevel.count == 1 and File.directory? toplevel[0]
        Vsh.mv toplevel.first, dest
      else
        Vsh.mv unpackdir, dest
        FileUtils.mkdir_p unpackdir # hack: put the dir back so mktmpdir can delete it
      end
    end
  end
end
