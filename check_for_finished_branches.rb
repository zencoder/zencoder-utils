#!/usr/bin/env ruby

# Get list of latest commit hashes for each branch, in this form:
#    34bde290ccc48944687c49d61dd7072d906b38bc	refs/heads/feature/resizing-modal
remote_hashes = `git ls-remote 2>/dev/null | grep -E "refs/heads/(feature|hotfix)/"`

# Convert to an array of pairs: [ ["34bde290ccc48944687c49d61dd7072d906b38bc", "refs/heads/feature/resizing-modal"] ]
remote_hashes = remote_hashes.split(/\n/).map { |line| line.split(/\s+/).compact }

# Check for finished features (merged to master)
remote_hashes.each do |hash,branch|
  next unless branch.to_s.include?('refs/heads/feature')

  # Check for remote branches containing the hash, and see if origin/master is in the mix.
  merged_to_master = system("git branch --contains #{hash} -r 2>&1 | grep --quiet origin/master")

  puts "Branch #{branch.sub('refs/heads/','')} exists, despite already being merged to master." if merged_to_master
end

# Check for finished hotfixes (merged to production)
remote_hashes.each do |hash,branch|
  next unless branch.to_s.include?('refs/heads/hotfix')

  # Check for remote branches containing the hash, and see if origin/master is in the mix.
  merged_to_production = system("git branch --contains #{hash} -r 2>&1 | grep --quiet origin/production")
  puts "Branch #{branch.sub('refs/heads/','')} exists, despite already being merged to production." if merged_to_production
end


