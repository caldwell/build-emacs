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
    options[:depth] ||= 0;
    puts "#{'='*(options[:depth]+1)*2}> Processing #{exe}" if Vsh.verbose

    obj = MachO.new(exe)

    rel_path_to_dest = "@loader_path/" + Pathname.new(@dest_dir).relative_path_from(Pathname.new(exe).dirname).to_s.sub(/^\.$/,'')

    if obj.id
      # Make the new id match the imports so we don't accidentally get our deps overridden
      obj.id = '@rpath/' + Pathname.new(exe).relative_path_from(Pathname.new(@dest_dir)).to_s
    end

    orig_rpaths = obj.rpaths
    obj.rpaths.each {|rp| obj.delete_rpath(rp) }
    obj.add_rpath(rel_path_to_dest)

    stray={ lib:[], path:[], exe:exe }
    obj.dylibs.dup.each do |dylib|
      # HACK! I know we just added all that nice code to handle frameworks and rpaths (and
      # it works!), but it turns out codesign doesn't like this library. Perhaps because
      # it's named like a system library? Anyway, it appears to be compatible with the
      # actual system library, so lets just point to that, remove the rpath and be done.
      if dylib == "@rpath/CoreFoundation.framework/Versions/A/CoreFoundation"
        obj.rename_dylib(dylib, "/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation")
        next
      end
      (m,orig_dep,dep_base, dep_path,lib) = dylib.match(%r,^((#{@dep_dir}|@rpath)(/[^ ]+)*/(lib[^/ ]+))$,).to_a
      (m,orig_dep,dep_base, dep_path,framework,lib) = dylib.match(%r,^((#{@dep_dir}|@rpath)(/[^ ]+)*/([^/ ]+\.framework)(/[^ ]+)+)$,).to_a unless m
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
          orig_path = File.join(dep_base, dep_path||"", lib)
          orig_lib = orig_path
          new_dep_lib = lib
        end

        if dep_base == "@rpath"
          # A little tricky, but we have to look for the dependency relative to the original exe.
          # The roots of the dependency trees (Emacs.app contents after `make install`) have not been moved so
          # their origin is just themselves.
          origin = @origin[File.basename(exe)] || exe
          rpaths = orig_rpaths.map {|path| path.sub(/@loader_path/, File.dirname(origin)) }

          rpath = rpaths.select {|p| File.exist?(orig_dep.sub(/@rpath/, p)) }
                        .first or raise "Can't resolve rpath #{orig_dep} in #{rpaths.inspect}"
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

        obj.rename_dylib(orig_dep, File.join("@rpath", new_dep_lib))

        unless @origin[new_dep_lib]
          Vsh.mkdir_p(@dest_dir)
          if framework
            Vsh.cp_r(orig_path, @dest_dir)
            Vsh.chmod_R("u+w", File.join(@dest_dir, File.basename(orig_path))) # technically not needed, but fixes `rsync -E` in make-dmg on macOS 26
          else
            Vsh.cp(orig_path, File.join(@dest_dir, new_dep_lib))
            Vsh.chmod("u+w", File.join(@dest_dir, new_dep_lib))                # ditto
          end
          @origin[new_dep_lib] = orig_path
          copy_libs(File.join(@dest_dir, new_dep_lib), options.merge(depth: options[:depth]+1)) # Copy lib's deps, too
        end
      elsif !dylib.match(%r{^(?:
                               /System/                                    |
                               @(loader|executable)_path/                  |
                               /usr/lib/lib(System|objc|c\+\+)\.\w+\.dylib |
                               /usr/lib/libresolv.\w+.dylib                |
                               #{Regexp.escape(File.basename(@dest_dir))}  |
                             )
                        }x)
        stray[:lib].push(dylib)
      end
    end
    stray[:path].concat(Vsh.capture(*%W"strings #{exe}").split("\n").select {|l| l.match(%r{/nix/store/}) })
    @strays.concat(stray[:lib].any? || stray[:path].any? ? [stray] : [])
  end
end

class MachO
  def initialize(exe)
    @exe = exe
    @lc = Vsh.capture(*%W"otool -l #{@exe}").split(/^(?=(?:Load command|Section))/m)

    # Load command 4
    #           cmd LC_ID_DYLIB
    #       cmdsize 104
    #          name /nix/store/bzmg171wk7x7vkhnr1m51v6yphb7cfm7-mpfr-4.2.2/lib/libmpfr.6.dylib (offset 24)
    #    time stamp 1 Wed Dec 31 16:00:01 1969
    #       current version 9.2.0
    # compatibility version 9.0.0
    @id = @lc.select {|c| /^\s*cmd LC_ID_DYLIB$/ =~ c}
             .map { |id| /^\s*name\s+(?<name>.*)\s+\(offset[^)]+\)$/ =~ id && name }
             .first

    # Load command 48
    #           cmd LC_RPATH
    #       cmdsize 40
    #          path @loader_path/lib-arm64-11 (offset 12)
    @rpaths = @lc.select {|c| /^\s*cmd LC_RPATH$/ =~ c}
                 .map {|rp| /^\s*path\s+(?<path>.*)\s+\(offset[^)]+\)$/ =~ rp && path }

    # Load command 11
    #           cmd LC_LOAD_DYLIB
    #       cmdsize 112
    #          name /nix/store/k2rw8djc491iqmf9lm6y1yk5939hbds1-gmp-with-cxx-6.3.0/lib/libgmp.10.dylib (offset 24)
    #    time stamp 2 Wed Dec 31 16:00:02 1969
    #       current version 16.0.0
    # compatibility version 16.0.0
    @dylibs = @lc.select {|c| /^\s*cmd LC_LOAD_DYLIB$/ =~ c}
                 .map {|rp| /^\s*name\s+(?<name>.*)\s+\(offset[^)]+\)$/ =~ rp && name }
  end

  def id
    @id
  end

  def id=(new_id)
    with_writable_mode(@exe) {
      Vsh.system(*%W"install_name_tool -id #{new_id} #{@exe}")
    }
    @id = new_id
  end

  def rpaths
    @rpaths
  end

  def add_rpath(rpath)
    with_writable_mode(@exe) {
      Vsh.system(*%W"install_name_tool -add_rpath #{rpath} #{@exe}")
    }
    @rpaths.push(rpath)
  end

  def delete_rpath(rpath)
    with_writable_mode(@exe) {
      Vsh.system(*%W"install_name_tool -delete_rpath #{rpath} #{@exe}")
    }
    @rpaths.delete_at(@rpaths.index(rpath))
  end

  def dylibs
    @dylibs
  end

  def rename_dylib(old_name, new_name)
    with_writable_mode(@exe) {
      Vsh.system(*%W"install_name_tool -change #{old_name} #{new_name} #{@exe}")
    }
    @dylibs.map! {|lib| lib == old_name ? new_name : old_name }
  end

  def with_writable_mode(file)
    old = File.stat(file).mode
    File.chmod(0775, file)
    yield
    File.chmod(old, file)
  end
end
