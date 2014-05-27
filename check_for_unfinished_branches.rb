#!/usr/bin/env ruby

# Don't try to check anything if we don't have a network connection
if !system("git fetch 2>&1 > /dev/null")
  raise "Error performing `git fetch`, check your network or something"
end

# Get JUST the branch names
branches = `git ls-remote 2>/dev/null | grep -o -E "(feature|hotfix|release)/.+"`.split("\n")

branches_and_authors = {}

# Get all the branches (and their author) that have commits that aren't in
# master and aren't merge commits.
branches.each do |b|
  author = `git log -1 --no-merges origin/#{b} ^origin/master | grep '^Author'`
  branches_and_authors[b] = author unless author.empty?
end

padding = branches_and_authors.keys.map(&:size).max

branches_and_authors.each do |branch, author|
  puts "Branch: #{branch.ljust(padding, " ")} -- #{author}"
end
