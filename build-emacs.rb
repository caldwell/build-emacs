require 'shell'
require 'fileutils'


def build_emacs(src_dir, out_name, options)
  out_name = out_name + ".tar.bz2"
  puts "building emacs: #{src_dir} => #{out_name}"
  options[:cc] ||= "cc"
  options[:extra_cc_options] ||= ''

  vsystem = lambda do |*args|
    puts "+ #{args}" if options[:verbose]
    system *args
  end

  FileUtils.cd(src_dir) do
    sh = Shell.new
    vsystem.call('test -f ./configure || ./autogen.sh || ./autogen/copy_autogen')

    sh[?e, 'configure'] || sh.system('./autogen.sh') || sh.system('./autogen/copy_autogen')

    min_os_flag = options[:min_os] ? "-mmacosx-version-min=#{options[:min_os]}" : ""
    host_flags = options[:host] ? ["--host=#{options[:host]}", '--build=i686-apple-darwin'] : []

    ENV['CC']="#{options[:cc]} #{options[:min_os_flag]} #{options[:extra_cc_options]}"
    vsystem.call(*(%W"./configure --with-ns")+host_flags) || throw("configure failed")
    vsystem.call(*(%W"make clean install")) || throw("make failed")
    FileUtils.cd('nextstep') { vsystem.call(*(%W"tar cjf #{out_name} Emacs.app")) }
  end
  FileUtils.mv(File.join(src_dir, 'nextstep', out_name), out_name, :force => true)
  out_name
end
