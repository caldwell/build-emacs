#!/usr/bin/ruby

def numify(version_string)
  version_string.sub(/^(\d+)\.(\d+)(?:\.(\d+))?$/) { |m| $1.to_i*10000 + $2.to_i*100 + ($3 || "0").to_i*1 }.to_i
end

def osascript(script)
  system 'osascript', *script.split(/\n/).map { |line| ['-e', line] }.flatten
end


versions = Hash[*Dir["#{File.dirname($0)}/Emacs-*"].map { |file| [ numify(file.sub(/^.*-(.+)$/, '\1')), file] }.flatten]
version = numify(`sw_vers -productVersion`)
if highest_compatible_version =  versions.keys.select { |v| v <= version }.max
  exec [versions[highest_compatible_version], versions[highest_compatible_version]], *ARGV
end

osascript <<-ENDSCRIPT
  tell application "Finder"
    activate
    display dialog "This application will not run on your computer. Sorry!"
  end tell
ENDSCRIPT
