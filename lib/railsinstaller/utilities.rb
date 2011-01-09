module RailsInstaller::Utilities
  #
  # unzip:
  # Requires: rubyzip2 (gem install rubyzip2) # require "zip/zip"
  #
  def unzip(package)

    filename  = File.basename(package.url)
    base_path = File.dirname(filename)
    if package.target.nil?
      target_path = base_path
    else
      target_path = File.join(base_path, package.target)
    end
    regex     = Regexp.new(package.regex) unless package.regex.nil?
    files     = []

    printf " => Extracting #{filename} contents\n"

    Dir.chdir(RailsInstaller::Archives) do

      Zip::ZipFile.open(File.join(RailsInstaller::Archives, filename)) do |zipfile|

        printf "zipfile: #{zipfile.inspect}\n" if $Flags[:verbose]

        if regex

          entries = zipfile.entries.select do |entry|

            entry.name.match(regex)

          end

        else
          entries = zipfile.entries
        end

        FileUtils.mkdir_p(File.join(RailsInstaller::Stage, "bin"))

        entries.each do |entry|

          printf "DEBUG: Extracting #{entry.name}\n" if $Flags[:verbose]
          
          files << entry.name

          FileUtils.rm_f(entry.name) if File.exists?(entry.name)

          zipfile.extract(entry, entry.name)

          if File.exist?(File.join(RailsInstaller::Archives, entry.name))
            FileUtils.mv(
              File.join(RailsInstaller::Archives, entry.name),
              File.join(RailsInstaller::Stage, "bin", entry.name),
              :force => true
            )
          end

        end

      end

    end

    files

  end

  #
  # extract
  #
  # Used to extract a non-zip file using BSDTar
  #
  def extract(package)

    Dir.chdir(RailsInstaller::Archives) do

      filename = File.basename(package.url)

      unless File.exists?(filename)
        raise "ERROR: #{file} does not exist, did the download step fail?"
      end

      base_path     = RailsInstaller::Stage

      if package.target.nil?
        target_path = base_path
      else
        target_path = File.join(base_path, package.target)
      end
      bsdtar      = File.join(RailsInstaller::Stage, "bin", RailsInstaller::BSDTar.binary)
      sevenzip    = File.join(RailsInstaller::Stage, "bin", RailsInstaller::SevenZip.binary)

      printf " => Extracting '#{filename}' into '#{target_path}'\n" if $Flags[:verbose]

      FileUtils.mkdir_p(base_path) unless File.directory?(base_path)

      FileUtils.rm_rf(package.target) if (File.directory?(target_path) && target_path != base_path)

      archive = File.join(RailsInstaller::Archives, filename)

      Dir.chdir(RailsInstaller::Stage) do

          case filename
          when /(^.+\.tar)\.z$/, /(^.+\.tar)\.gz$/, /(^.+\.tar)\.bz2$/, /(^.+\.tar)\.lzma$/, /(^.+)\.tgz$/
            command = %Q("#{bsdtar}" -xf "#{archive}") #  > NUL 2>&1")
          when /^.+\.7z$/
            command = %Q("#{sevenzip}" x -t7z -o#{target_path} "#{archive}") #  > NUL 2>&1")
          when /^.+sfx\.exe$/
            command = %Q("#{sevenzip}" x -t7z -sfx -o#{target_path} #{archive})
          when /(^.+\.zip$)/
            if File.exist?(sevenzip) # Use bsdtar once we already have it
              command = %Q("#{sevenzip}" x -o#{target_path} #{archive})
              # command = %Q("#{bsdtar}" -xf "#{archive}") #  > NUL 2>&1")
            else
              # For the unzip case we can return a list of extracted files.
              return unzip(package)
            end
          else
            raise "\nERROR:\n  Cannot extract #{archive}, unhandled file extension!\n"
        end

        if $Flags[:verbose]
          puts(sh(command))
        else
          sh command
        end

      end
    end

  end


  #
  # install_utility()
  #
  # Requires: open-uri
  #
  def install_utility

    # TODO: Merge this into download, simply check if object has a .binary attribute.
    if File.exists?(File.join(RailsInstaller::Stage, "bin", binary))

      printf "#{File.join(RailsInstaller::Stage, "bin", binary)} exists.\nSkipping download, extract and install.\n"

    else

      printf " => Downloading and extracting #{binary} from #{utility.url}\n"

      FileUtils.mkdir_p(RailsInstaller::Stage) unless File.directory?(RailsInstaller::Stage)

      Dir.chdir(RailsInstaller::Stage) do

        filename = File.basename(utility.url)

        FileUtils.rm_f(filename) if File.exist?(filename)

        # Utilities are small executables, thus using open-uri to download them is fine.
        open(utility.url) do |temporary_file|

          File.open(filename, "wb") do |file|

            file.write(temporary_file.read)

          end

        end

        extract(binary)
        printf " => Instaling #{binary} to #{File.join(RailsInstaller::Stage, "bin")}\n"

        FileUtils.mkdir_p(RailsInstaller::Stage, "bin") unless File.directory?(RailsInstaller::Stage, "bin")

        FileUtils.mv(
          File.join(RailsInstaller::Stage, binary),
          File.join(RailsInstaller::Stage, "bin", binary),
          :force => true
        )

      end
    end

  end

  #
  # build_gems
  #
  # loops over each gemname and triggers it to be built.
  def build_gems(ruby_path, gems)

    if gems.is_a?(Array)

      gems.each do |name|

        build_gem(ruby_path, name)

      end

    elsif gems.is_a?(Hash)

      gems.each_pair do |name, version |

        build_gem(ruby_path, name,version)

      end

    else

      build_gem(gems)

    end

  end

  def build_gem(ruby_path, gemname, options = {})

    printf " => Staging gem #{gemname}\n" if $Flags[:verbose]

    %w(GEM_HOME GEM_PATH).each { |variable| ENV.delete(variable)}

    command = %Q(#{File.join(ruby_path, "bin", "gem")} install #{gemname})

    command += %Q( -v#{options[:version]} ) if options[:version]

    command += %Q( --no-rdoc --no-ri )

    command += options[:args] if options[:args]

    sh command

  end

  #
  # sh
  #
  # Runs Shell commands, single point of shell contact.
  #
  def sh(command, options = {})

    stage_bin_path = File.join(RailsInstaller::Stage, "bin")

    ENV["PATH"] = "#{stage_bin_path};#{ENV["PATH"]}" unless ENV["PATH"].include?(stage_bin_path)

    printf "\nDEBUG: > %s\n\n", command if $Flags[:verbose]

    %x(#{command})

  end


  def log(text)
    printf %Q[#{text}\n]
  end

  def section(text)
    printf %Q{\n#\n# #{text}\n#\n\n}
  end
end
