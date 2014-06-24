#!/usr/bin/ruby

class NumifiedVersion
  attr_accessor :str, :num
  def initialize(version_string)
    @str = version_string
    @num = @str.sub(/^(\d+)\.(\d+)(?:\.(\d+))?$/) { |m| $1.to_i*10000 + $2.to_i*100 + ($3 || "0").to_i*1 }.to_i
  end
  def to_s; @str; end
  def ==(a);  return @num == a.num; end
  def <=(a);  return @num <= a.num; end
  def <=>(a); return @num <=> a.num; end
end


def osascript(script)
  system 'osascript', *script.split(/\n/).map { |line| ['-e', line] }.flatten
end

version = NumifiedVersion.new(`sw_vers -productVersion`)
arch=`uname -m`.chomp

emacs = Dir["#{File.dirname($0)}/Emacs-*"].map { |file| file.match(/^.*-(.+)-(.+)$/) && {:arch=>$1, :version=>NumifiedVersion.new($2), :exe=>file} }
        .select { |v| v[:arch] == arch && v[:version] <= version }
        .sort { |a,b| a[:version] <=> b[:version] }
        .last

if emacs
  # Emacs.app sticks Emacs.app/Contents/MacOS/{bin,libexec} on the end of the PATH when it starts, so if we
  # stick our own architecture dependent paths on the end of the PATH then they will override Emacs's paths
  # while not affecting any user paths.
  base_dir=File.absolute_path(File.dirname($0))
  ENV['PATH'] += File.join(base_dir,     "bin-#{emacs[:arch]}-#{emacs[:version]}") + ':' +
                 File.join(base_dir, "libexec-#{emacs[:arch]}-#{emacs[:version]}")
  exec [emacs[:exe], emacs[:exe]], *ARGV
end

osascript <<-ENDSCRIPT
  tell application "Finder"
    activate
    display dialog "This application will not run on your computer. Sorry!"
  end tell
ENDSCRIPT
