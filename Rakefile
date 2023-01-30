require "bundler/gem_tasks"
require "rake/testtask"
require "bundler"

Bundler.setup

Rake::TestTask.new do |t|
  t.libs << "spec"
  t.test_files = FileList["spec/*_spec.rb"]
  t.verbose = true
end

task :default => :test

namespace :demo do
  task :build do
    Dir.chdir('demo') { sh 'rake' }
  end
end

namespace :packages do
  # TODO: add tests and support for Vite
  desc "Build & test the Node version of Ruby2JS plus frontend bundling packages"
  task :test do

    Dir.chdir 'packages/ruby2js' do
      sh 'yarn install' unless File.exist? 'yarn.lock'
      sh 'yarn build'
      sh 'yarn test'
    end

    Dir.chdir 'packages/esbuild-plugin' do
      sh 'yarn install' unless File.exist? 'yarn.lock'
      sh 'yarn test'
    end

    Dir.chdir 'packages/rollup-plugin' do
      npm_root = `npm root`.strip
      sh 'yarn install' unless File.exist? 'yarn.lock'
      sh "cp ../ruby2js/ruby2js.js #{npm_root}/@ruby2js/ruby2js/ruby2js.js"
      sh 'yarn test'
    end

    Dir.chdir 'packages/webpack-loader' do
      npm_root = `npm root`.strip
      sh 'yarn install' unless File.exist? 'yarn.lock'
      sh "cp ../ruby2js/ruby2js.js #{npm_root}/@ruby2js/ruby2js/ruby2js.js"
      sh 'yarn prepare-release'
      sh 'yarn test'
    end
  end
end

namespace :npm do
  desc "Release the Node version of Ruby2JS"
  task :release do
    Dir.chdir("packages/ruby2js") do
      sh "npm publish"
    end
  end
end

desc "Test the Gem and Node versions of Ruby2JS as well as frontend bundling packages"
task test_all: [:test, "packages:test"]

desc "Test & release both the Gem and Node versions of Ruby2JS simultaneously"
task release_core: [:test_all, :release, "npm:release"]
