# coding: utf-8
require 'fileutils'

def bright_white_on_red(msg)
  "\e[97;41m#{msg}\e[0m"
end

class VerboseShell
  @verbose = 0
  class << self
    attr_accessor :verbose
    def verbose=(val); @verbose = val == true ? 1 : (val || 0); end

    def system_trace(*args)
      return unless @verbose > 0
      puts "+ "+args.map{|a| a =~ /\s/ ? '"'+a+'"' : a}.join(' ') # TODO: Fix quoting so it's more shell-like
    end

    class ShellError < RuntimeError
      attr_accessor :output, :cmd, :exit_code
      def initialize(output, cmd, exit_code)
        @output = output
        @cmd = cmd
        @exit_code = exit_code
      end

      def message
        "\n\n"+(['']*20+@output.split("\n"))[-20..-1].join("\n").lstrip + "\n"+bright_white_on_red("💩  Command \"#{@cmd[0]}\" returned #{@exit_code}")
      end
      def to_s; message; end
    end

    def system(*args)
      system_trace *args
      args, opts = args.last.is_a?(Hash) ? [args[0..-2], args.last.dup] : [args, {}]
      if opts.delete(:loud) or @verbose > 0
        Kernel.system(*args, opts) or raise ShellError.new('', args, $?.exitstatus)
      else
        output = IO.popen(args, opts.merge({:err => [:child, :out]})) {|io| io.read}
        raise ShellError.new(output, args, $?.exitstatus) if $? != 0
      end
      $?
    end

    def system_noraise(*args)
      system *args
    rescue ShellError => e
      e.exit_code
    end

    def capture(*args) # ``
      system_trace *args
      IO.popen(args + (@verbose == 0 ? [{:err => "/dev/null"}] : []), "r") {|io| io.read}.strip
    end

    def which?(exe)
      system_trace 'which', exe
      [exe, *ENV['PATH'].split(File::PATH_SEPARATOR).map {|p| File.join(p, exe)}].find {|f| File.executable?(f)}
    end

    def install_D(source, dest)
      system_trace 'install', '-D', source, dest
      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.install(source, dest)
    end

    def method_to_a(method)
      a = method.to_s.split('_')
      a[1] = "-#{a[1]}" if a[1]
      a
    end

    def chmod_formatter(method, mode, file)
      method_to_a(method) + [mode.class == String ? mode : sprintf("%04o", mode)] + (file.class == Array ? file : [file])
    end
    def chmod_R_formatter(method, mode, file)
      chmod_formatter(method, mode, file)
    end
    def chown_formatter(method, user, group, file)
      method_to_a(method) + [[user,group && ":#{group}"].select{|x|x}.join('')] + (file.class == Array ? file : [file])
    end
    def chown_R_formatter(method, user, group, file)
      chown_formatter(method, user, group, file)
    end

    def method_missing(method, *args, &block)
      opts = args.last.is_a?(Hash) ? args.pop : {}
      system_trace self.respond_to?("#{method}_formatter") ? self.send("#{method}_formatter", method, *args, **opts)
                   : method_to_a(method) + args + (opts == {} ? [] : [opts.inspect])
      FileUtils.send(method, *args, **opts, &block)
    end
  end
end
