#!/usr/bin/ruby
# Copyright © 2012-2016 David Caldwell <david@porkrind.org>
#
# This launcher code is from emacsformacosx.com and is not part of Emacs
# proper. It exists so that there can be a single download that contains
# binaries for all supported Mac OS X versions.
#
# Why not just use a fat binary? Because fat binaries can only hold 1 of
# each architecture and Emacs has multiple x86_64 architectures binaries.
#
# Why are there multiple x86_64 binaries? Because the Emacs source does OS
# feature detection at compile time instead of at run-time. So if you build
# Emacs on 10.9 then it will contain hard-coded calls to 10.9 APIs and will
# not run on 10.6. If you compile it on 10.6, then it will also run on 10.9,
# but it won't take advantage of any of the features in 10.9.
#
# Bug reports for this launcher should go here:
#   https://github.com/caldwell/build-emacs
#
# Licence:
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.

require 'rubygems'

def osascript(script)
  system 'osascript', *script.split(/\n/).map { |line| ['-e', line] }.flatten
end

version = Gem::Version.new(`sw_vers -productVersion`)
arch=`uname -m`.chomp

# Support direct symlinks to Emacs.app/Contents/MacOS/Emacs
exe = $0
while (File.symlink? exe) do; exe = File.readlink exe; end

emacs = Dir["#{File.dirname(exe)}/Emacs-*"].map { |file| file.match(/^.*-(.+)-(.+)$/) && {:arch=>$1, :_version=>$2, :version=>Gem::Version.new($2.gsub('_','.')), :exe=>file} } \
        .select { |v| v[:arch] == arch && v[:version] <= version } \
        .sort { |a,b| a[:version] <=> b[:version] } \
        .last

# This dedups environment variables. Mac OS X 10.10 (Yosemite) always gives
# us 2 PATHs(!!)  See: https://github.com/caldwell/build-emacs/issues/39
# Ruby is written such that the last key wins, which is what we want since
# the first PATH is always the boring PATH=/usr/bin:/bin:/usr/sbin:/sbin
eh={}; ENV.each {|k,v| eh[k]=v} # Should be eh=ENV.to_h, but ENV in Ruby 1.8.7 doesn't have to_h.
ENV.replace({})
ENV.replace(eh)

if emacs
  # Emacs.app sticks Emacs.app/Contents/MacOS/{bin,libexec} on the end of the PATH when it starts, so if we
  # stick our own architecture dependent paths on the end of the PATH then they will override Emacs's paths
  # while not affecting any user paths.
  base_dir=File.expand_path(File.dirname(exe))
  arch_version = emacs[:arch] + '-' + emacs[:_version] # see the 'combine-and-package' script in the build-emacs repo
  ENV['PATH'] += ':' + File.join(base_dir,     "bin-#{arch_version}") +
                 ':' + File.join(base_dir, "libexec-#{arch_version}")
  exec [emacs[:exe], emacs[:exe]], *ARGV
end

osascript <<-ENDSCRIPT
  tell application "Finder"
    activate
    display dialog "This application will not run on your computer. Sorry!"
  end tell
ENDSCRIPT
