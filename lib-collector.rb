#  Copyright © 2014-2025 David Caldwell
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

class LibCollector
  def initialize(dep_dir, dest_dir)
    @dep_dir = dep_dir
    @dest_dir = dest_dir
    @origin = {}
    @strays = []
  end

  def strays
    @strays
  end

  def copy_libs(exe, options={})
    rel_path_to_dest = "@loader_path/" + Pathname.new(@dest_dir).relative_path_from(Pathname.new(exe).dirname).to_s.sub(/^\.$/,'')
    options[:rpath] ||= [];
    options[:depth] ||= 0;
    puts "#{'='*(options[:depth]+1)*2}> Processing #{exe}" if Vsh.verbose
    new_id = Pathname.new(exe).relative_path_from(Pathname.new(@dest_dir).dirname).to_s
    with_writable_mode(exe) {
      # remove our local build path from the id to leak as litle as possible (not that it really matters)
      Vsh.system(*%W"install_name_tool -id #{new_id} #{exe}")
    }
    stray={ lib:[], path:[], exe:exe }
    Vsh.capture(*%W"otool -L #{exe}").split("\n").each do |line| # ex:   /Volumes/sensitive/src/build-emacs/brew/opt/gnutls/lib/libgnutls.30.dylib (compatibility version 37.0.0, current version 37.6.0)
      # HACK! I know we just added all that nice code to handle frameworks and rpaths (and
      # it works!), but it turns out codesign doesn't like this library. Perhaps because
      # it's named like a system library? Anyway, it appears to be compatible with the
      # actual system library, so lets just point to that, remove the rpath and be done.
      if %r{^\s+(?<cf>@rpath/CoreFoundation.framework/Versions/A/CoreFoundation)\s+} =~ line
        with_writable_mode(exe) {
          Vsh.system(*%W"install_name_tool -change #{cf} /System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation #{exe}") # Wheeee!
          Vsh.capture(*%W"otool -l #{exe}").split(/^(?=(?:Load command|Section))/m)
            .select {|c| /^\s*cmd LC_RPATH$/ =~ c}.map {|rp| /^\s*path\s+(?<path>.*)\s+\(offset[^)]+\)$/ =~ rp && path }
            .each {|rpath| Vsh.system(*%W"install_name_tool -delete_rpath #{rpath} #{exe}") }
        }
        next
      end
      (m,orig_dep,dep_base, dep_path,lib)=line.match(%r,^\s+((#{@dep_dir}|@rpath)(/[^ ]+)+/(lib[^/ ]+))\s,).to_a
      (m,orig_dep,dep_base, dep_path,framework,lib)=line.match(%r,^\s+((#{@dep_dir}|@rpath)(/[^ ]+)*/([^/ ]+\.framework)(/[^ ]+)+)\s,).to_a unless m
      if m
        # We have 2 boolean conditons (rp=rpath, fr=framework), so there are 4 cases we need to cover:
        #        Rename:   orig_dep                -> rel_path_to_dest/new_dep_lib                   Copy: orig_path                  -> dest                  Recurse: dest/new_dep_lib
        # -- --  #{dep_dir}/.../libx.dylib         -> @loader_path/#{dest:rel}/libx.dylib            #{dep_dir}/.../libx.dylib        -> #{dest}/libx.dylib    #{dest}/libx.dylib
        # -- fr  #{dep_dir}/.../X.framework/.../X  -> @loader_path/#{dest:rel}/X.framework/.../X     #{dep_dir}/.../X.framework       -> #{dest}/X.framework   #{dest}/X.framework/.../X
        # rp --  @rpath/.../libx.dylib             -> @loader_path/#{dest:rel}/libx.dylib            <resolved-rpath>/.../libx.dylib  -> #{dest}/libx.dylib    #{dest}/libx.dylib
        # rp fr  @rpath/.../X.framework/.../X      -> @loader_path/#{dest:rel}/X.framework/.../X     <resolved-rpath>/.../X.framework -> #{dest}/X.framework   #{dest}/X.framework/.../X
        if framework
          orig_path = File.join(dep_base, dep_path||"", framework)
          orig_lib = File.join(orig_path, lib)
          new_dep_lib = File.join(framework, lib)
        else
          orig_path = File.join(dep_base, dep_path, lib)
          orig_lib = orig_path
          new_dep_lib = lib
        end

        if dep_base == "@rpath"
          # Accumulating our rpaths here isn't technically correct--If some random binary
          # down the chain has an rpath this makes it pollute our lookups from then
          # on. Practically it should be ok since we are currently pulling from Nix and
          # everything _should_ be sharing the same stuff anyway.
          options[:rpath] += Vsh.capture(*%W"otool -l #{exe}").split(/^(?=(?:Load command|Section))/m)
                               .select {|c| /^\s*cmd LC_RPATH$/ =~ c}.map {|rp| /^\s*path\s+(?<path>.*)\s+\(offset[^)]+\)$/ =~ rp && path }
          rpath = options[:rpath].select {|p| File.exist?(orig_dep.sub(/@rpath/, p)) }.first or raise "Can't resolve rpath #{orig_dep} in #{rpaths}"
          orig_path = orig_path.sub(/@rpath/, rpath)
          orig_lib = orig_lib.sub(/@rpath/, rpath)
        end

        while @origin[new_dep_lib] && @origin[new_dep_lib] != orig_path
          # Not sure how to rename frameworks and we don't actually have any in our deps at the moment to test with...
          raise "Sorry, one framework with different versions is not supported (#{@origin[new_dep_lib]} vs #{orig_path})" if framework

          count = (count||0) + 1
          puts "Duplicate dependency:\n    #{@origin[new_dep_lib]}\n    #{orig_path}"
          parts = new_dep_lib.split('.')
          parts[0] += "-dup-#{count}"
          new_dep_lib = parts.join('.')
          puts "  Retrying with new name #{new_dep_lib}"
        end


        with_writable_mode(exe) {
          Vsh.system(*%W"install_name_tool -change #{orig_dep} #{File.join(rel_path_to_dest, new_dep_lib)} #{exe}") # Point to where we're about to copy the lib
        }

        unless @origin[new_dep_lib]
          Vsh.mkdir_p(@dest_dir)
          if framework
            Vsh.cp_r(orig_path, @dest_dir)
          else
            Vsh.cp(orig_path, File.join(@dest_dir, new_dep_lib))
          end
          @origin[new_dep_lib] = orig_path
          copy_libs(File.join(@dest_dir, new_dep_lib), options.merge(depth: options[:depth]+1)) # Copy lib's deps, too
        end
      elsif line.strip.start_with?("#{new_id} ")
      elsif !line.match(%r{^(?:
                             \s+(?:
                               /System/                                    |
                               @(loader|executable)_path/                  |
                               @rpath/                                     |
                               /usr/lib/lib(System|objc|c\+\+)\.\w+\.dylib |
                               /usr/lib/libresolv.\w+.dylib                |
                               #{Regexp.escape(File.basename(@dest_dir))}
                             )
                           )|
                           ^#{Regexp.escape(exe)}:
                        }x)
        stray[:lib].push(line)
      end
    end
    stray[:path].concat(Vsh.capture(*%W"strings #{exe}").split("\n").select {|l| l.match(%r{/nix/store/}) })
    @strays.concat(stray[:lib].any? || stray[:path].any? ? [stray] : [])
  end
end

