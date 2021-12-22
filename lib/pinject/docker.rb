# frozen_string_literal: true

require 'docker'
require 'digest/md5'
require 'fileutils'
module Pinject
  class Docker
    attr_reader :log

    def initialize(image_name, log: false)
      @image_name = image_name
      @log = log
    end

    def inject_build(repo)
      if r = detect_os
        Pinject.log.info "detect os #{r.inspect}" if log
        upd = update_cmd(r[:dist], r[:version])
        if upd
          df = docker_file(@image_name, upd, r[:user])
          ::Docker::Image.build(
            df,
            't' => repo
          ) do |v|
            Pinject.log.info v if log
          end
        else
          raise UnsupportedDistError, "unsupport os dist:#{r[:dist]} version:#{r[:version]}"
        end
      end
    end

    private

    def detect_os
      ::Docker::Container.all(all: true).each do |c|
        c.delete(force: true) if c.info['Names'].first == "/#{container_name}"
      end

      container = ::Docker::Container.create({
                                               'name' => container_name,
                                               'Image' => image.id,
                                               'Entrypoint' => '',
                                               'Cmd' => ['/opt/detector']
                                             })

      result = nil
      t = Thread.new { container.attach { |stream, chunk| result = chunk.chomp if stream == :stdout } }
      container.start
      t.join

      if result
        dist, version, user = result.split(%r{:|/})

        {
          dist: dist,
          version: version,
          user: user
        }
      end
    end

    def docker_file(image, cmd, user)
      t = <<~EOS
        FROM %s
        USER root
        RUN %s
        USER %s
      EOS
      format(t, image, cmd, user)
    end

    def container_name
      Digest::MD5.hexdigest(@image_name)[0..10]
    end

    def image
      Pinject.log.info 'start detect os' if log
      ::Docker.options[:read_timeout] = 300
      begin
        i = ::Docker::Image.create('fromImage' => @image_name)
      rescue StandardError => e
        Pinject.log.error "failed create container #{e.inspect}" if log
        raise e
      end

      t = Tempfile.open('detector') do |f|
        f.puts detector_code
        f
      end
      FileUtils.chmod(0o755, t.path)
      i.insert_local('localPath' => t.path, 'outputPath' => '/opt/detector')
    end

    def update_cmd(dist, version)
      r = case dist
          when 'ubuntu', 'debian'
            ['apt-get update -qqy', 'apt-get upgrade -qqy', 'apt-get clean', 'rm -rf /var/lib/apt/lists/*']
          when 'alpine'
            ['apk update', 'apk upgrade --no-cache']
          when 'centos'
            case version
            when '5', '6'
              nil
            else
              ['yum update -y']
            end
      end
      r&.join(' && ')
    end

    def detector_code
      <<~EOS
        #!/bin/sh
        if [ -f /etc/lsb-release ]; then
            . /etc/lsb-release
            OS=$DISTRIB_ID
            VER=`echo $DISTRIB_RELEASE | awk -F. '{ print $1 }'`
        elif [ -f /etc/debian_version ]; then
            OS=debian
            VER=`cat /etc/debian_version | awk -F. '{ print $1 }'`
        elif [ -f /etc/redhat-release ]; then
            OS=centos
            VER=`cat /etc/redhat-release | sed -e 's/.*\\s\\([0-9]\\)\\..*/\\1/'`
        elif [ -f /etc/alpine-release ]; then
            OS=alpine
            VER=`cat /etc/alpine-release | awk -F. '{ print $1 }'`
        else
            OS="other"
            VER="unknown"
        fi
        echo $OS/$VER:`whoami` | tr '[:upper:]' '[:lower:]'
      EOS
    end
  end
end
