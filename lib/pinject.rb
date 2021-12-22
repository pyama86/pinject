# frozen_string_literal: true

require_relative 'pinject/version'
require_relative 'pinject/docker'
require 'logger'

module Pinject
  def self.log
    @log ||= Logger.new($stdout)
  end

  class Error < StandardError; end
  class UnsupportedDistError < StandardError; end
  # Your code goes here...
end
