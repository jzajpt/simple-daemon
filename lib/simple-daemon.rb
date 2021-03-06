require 'simple-daemon/version'
require 'fileutils'

module SimpleDaemon
  class Base

    def self.classname      
      underscore(name.split("::").last)
    end

    def self.pid_fn
      File.join(SimpleDaemon::WORKING_DIRECTORY, "#{classname}.pid")
    end

    def self.daemonize
      Controller.daemonize(self)
    end

    private

    def self.underscore(camel_cased_word)
      camel_cased_word.to_s.
      gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
      gsub(/([a-z\d])([A-Z])/,'\1_\2').
      tr("-", "_").
      downcase
    end
  end

  module PidFile
    def self.store(daemon, pid)
      File.open(daemon.pid_fn, 'w') {|f| f << pid}
    end

    def self.recall(daemon)
      IO.read(daemon.pid_fn).to_i rescue nil
    end
    
    # Returns true if PID file is sane (process exists)
    def self.sane?(daemon)
      pid = recall(daemon)
      Process.getpgid(pid)
      true
    rescue Errno::ESRCH
      false
    end
  end

  module Controller
    def self.daemonize(daemon)
      case !ARGV.empty? && ARGV[0]
      when 'start'
        start(daemon)
      when 'stop'
        stop(daemon)
      when 'status'
        status(daemon)
      when 'restart'
        stop(daemon)
        start(daemon)
      else
        puts "Invalid command. Please specify start, stop, restart or status."
        exit
      end
    end

    def self.start(daemon)
      fork do
        Process.setsid
        exit if fork
        if File.file?(daemon.pid_fn)
          puts "Pid file #{daemon.pid_fn} already exists.  Not starting."
          exit 1
        end
        PidFile.store(daemon, Process.pid)
        Dir.chdir SimpleDaemon::WORKING_DIRECTORY
        File.umask 0000
        log = File.new("#{daemon.classname}.log", "a")
        STDIN.reopen "/dev/null"
        STDOUT.reopen log
        STDERR.reopen STDOUT
        trap("TERM") {daemon.stop; exit}
        daemon.start
      end
      sleep(1) # Give daemon time to start
      if PidFile.sane?(daemon)
        puts "Daemon started."
      else
        puts "Daemon failed to start."
      end
    end

    def self.stop(daemon)
      if !File.file?(daemon.pid_fn)
        puts "Pid file not found. Is the daemon started?"
        exit
      end
      pid = PidFile.recall(daemon)
      FileUtils.rm(daemon.pid_fn)
      pid && Process.kill("TERM", pid)
    rescue Errno::ESRCH
      puts "Pid file found, but process was not running. The daemon may have died."
    end
    
    def self.status(daemon)
      if !File.file?(daemon.pid_fn)
        puts "Daemon is not running."
      else
        if PidFile.sane?(daemon)
          puts "Daemon is running."
        else
          puts "Pid file found, but process is not present. It may have died."
        end
      end
      
    end
  end
end
