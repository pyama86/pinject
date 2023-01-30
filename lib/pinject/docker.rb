# frozen_string_literal: true

require 'docker'
require 'digest/md5'
require 'fileutils'
module Pinject
  class Docker
    attr_reader :log

    if %w[DOCKER_USER DOCKER_PASSWORD DOCKER_REGISTRY].all? { |a| ENV[a] }
      ::Docker.authenticate!(
        'username' => ENV['DOCKER_USER'],
        'password' => ENV['DOCKER_PASSWORD'],
        'serveraddress' => ENV['DOCKER_REGISTRY']
      )
    end

    def initialize(image_name, log: false)
      @image_name = image_name
      @log = log
    end

    def inject_build(repo)
      r = detect_os
      if r
        Pinject.log.info "detect os #{r.inspect}" if log
        upd = update_cmd(r[:dist], r[:version])
        if upd
          df = docker_file(@image_name, upd, r[:user])
          ::Docker::Image.build(
            df,
            't' => repo,
            'rm' => true,
            'nocache' => true
          ) do |v|
            Pinject.log.info v if log
          end
        else
          raise UnsupportedDistError, "unsupport os dist:#{r[:dist]} version:#{r[:version]}"
        end
      else
        raise UnsupportedDistError, "can't detect os"
      end
    end

    private

    def detect_os
      ::Docker.options[:read_timeout] = 300
      ::Docker::Container.all(all: true).each do |c|
        c.delete(force: true) if c.info['Names'].first == "/#{container_name}"
      end

      container = ::Docker::Container.create({
                                               'name' => container_name,
                                               'Image' => @image_name,
                                               'Entrypoint' => '',
                                               'Cmd' => ['/bin/sh', '/opt/detector']
                                             })

      container.store_file('/opt/detector', detector_code)
      result = nil
      err_result = nil
      container.run('/bin/sh /opt/detector')
      container.streaming_logs(stdout: true, stderr: true) do |stream, chunk|
        result = chunk.chomp if stream == :stdout
        err_result = chunk.chomp if stream == :stderr
      end

      Pinject.log.info "detect #{container_name} result:#{result.inspect} err:#{err_result.inspect}"
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

    def update_cmd(dist, version)
      r = case dist
          when 'ubuntu', 'debian'
            ['apt-get update -qqy', 'apt-get upgrade -qqy', 'apt-get clean', 'rm -rf /var/lib/apt/lists/*']
          when 'alpine'
            ['apk update', 'apk upgrade --no-cache']
          when 'oracle'
            case version
            when '7'
              ['yum update -y']
            when '8'
              ['microdnf update -y']
            end
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
        elif [ -f /etc/oracle-release ]; then
            OS=oracle
            VER=`cat /etc/oracle-release | sed -e 's/.*\\s\\([0-9]\\)\\..*/\\1/'`
        elif [ -f /etc/redhat-release ]; then
            OS=centos
            VER=`cat /etc/redhat-release | sed -e 's/.*\\s\\([0-9]\\)\\..*/\\1/'`
        elif [ -f /etc/alpine-release ]; then
            OS=alpine
            VER=`cat /etc/alpine-release | awk -F. '{ print $1 }'`
        elif [ -f /etc/os-release]; then
            . /etc/os-release
            OS=$ID
            VER=`echo $VERSION_ID | sed -e 's/"//g'`
        else
            OS="other"
            VER="unknown"
        fi
        echo $OS/$VER:`whoami` | tr '[:upper:]' '[:lower:]'
      EOS
    end
  end
end
