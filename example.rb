# frozen_string_literal: true

require './lib/pinject'
image = Pinject::Docker.new('mysql:8', log: true)
inject_image = image.inject_build('pyama:test') # run apt-get upgrade
# inject_image.push
