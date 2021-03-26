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

require 'fileutils'
require 'pathname'
require 'pp'

require_relative 'verbose-shell'
require_relative 'build'

class BuildDependencies

  def initialize(prefix)
    arm = `uname -m`.chomp == 'arm64'
    kernel_version = `uname -r`.chomp
    @prefix = File.expand_path(prefix)
    @deps = [ # Ordered carefullt so dependencies work.
      { source: "https://pkgconfig.freedesktop.org/releases/pkg-config-0.29.tar.gz", builddep: true,
        extra_configure_args: [*%W"--with-internal-glib --disable-debug --disable-host-tool", "LIBS=-framework corefoundation -framework cocoa"] },

      { source: "https://gmplib.org/download/gmp/gmp-6.2.1.tar.bz2" },
      { source: "https://ftp.gnu.org/gnu/nettle/nettle-3.7.2.tar.gz",
        extra_configure_args: %W"--disable-openssl" +
                              (arm ? %W"--build=aarch64-apple-darwin#{kernel_version}" : []) },
      { source: "https://ftp.gnu.org/pub/gnu/gettext/gettext-0.21.tar.gz" },
      { source: "https://www.gnupg.org/ftp/gcrypt/gnutls/v3.6/gnutls-3.6.15.tar.xz",
        extra_configure_args: %W"--with-included-unistring --with-included-libtasn1 --without-p11-kit",
        patches: %W"patches/gnutls-fallthrough.patch" },

      { source: "https://github.com/libffi/libffi/releases/download/v3.3/libffi-3.3.tar.gz" }
        .merge(arm ? { extra_configure_args: %W"--build=aarch64-apple-darwin#{kernel_version}" } : {}),

      { source: "https://digip.org/jansson/releases/jansson-2.13.1.tar.bz2" },
    ].map {|opts| Build.new(opts.merge(prefix: @prefix)) }
  end

  def clean
    Vsh.rm_rf(@prefix)
    @deps.each {|dep| dep.clean }
  end

  def add_to(key, val)
    ENV[key] = "#{val}:#{ENV[key]}"
  end

  def ensure
    add_to "PATH", "#{@prefix}/bin"
    add_to "PKG_CONFIG_PATH", "#{@prefix}/lib/pkgconfig"
    add_to "LIBRARY_PATH", "#{@prefix}/lib"
    add_to "CPATH", "#{@prefix}/include"

    @deps.each {|dep|
      dep.fetch()
      dep.build(@prefix)
    }
  end

  def export_sources(dir)
    Vsh.mkdir_p(dir)
    @deps.each {|dep|
      Vsh.ln(dep.archive_path, dir) unless dep.builddep
    }
  end
end
