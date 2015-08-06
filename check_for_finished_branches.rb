#!/usr/bin/env ruby

# Don't try to check anything if we don't have a network connection
if !system("git fetch 2>&1 > /dev/null")
  raise "Error performing `git fetch`, check your network or something"
end

# Get list of latest commit hashes for each branch, in this form:
#    34bde290ccc48944687c49d61dd7072d906b38bc	refs/heads/feature/resizing-modal
remote_hashes = `git ls-remote 2>/dev/null | grep -E "refs/heads/(feature|hotfix)/"`

# Convert to an array of pairs: [ ["34bde290ccc48944687c49d61dd7072d906b38bc", "refs/heads/feature/resizing-modal"] ]
remote_hashes = remote_hashes.split(/\n/).map { |line| line.split(/\s+/).compact }

# Check for finished features (merged to master)
remote_hashes.each do |hash,branch|
  next unless branch.to_s.include?('refs/heads/feature')

  simple_branch_name = branch.sub('refs/heads/','')

  # Check for remote branches containing the hash, and see if origin/master is in the mix.
  merged_to_master = system("git branch --contains #{hash} -r 2>&1 | grep --quiet origin/master")

  if merged_to_master
    responsible_merge_party = 'An Unknown Entity'
    responsible_merge_date = 'An Unkonwn Date'
    responsible_merge_commit = nil

    last_updated_info = `git log -n 1 #{hash}`
    last_updated_date = "#{$1} #{$2}" if last_updated_info =~ /Date: +\S+\s+(\S+\s+\S+)\s+\S+\s+(\S+)/ # Date:   Thu Jul 24 17:07:54 2014 -0700

    # Try to determine who did it, and when.
    merge_info = `git log origin/master ^origin/#{simple_branch_name} --ancestry-path --merges | grep -B 5 "Merge branch '#{simple_branch_name}'"`

    responsible_merge_party  = $1 if merge_info =~ /Author: +([^<]+?) *</     # Author: Matthew McClure <mmcclure@brightcove.com>
    responsible_merge_date   = "#{$1} #{$2}" if merge_info =~ /Date: +\S+\s+(\S+\s+\S+)\s+\S+\s+(\S+)/ # Date:   Thu Jul 24 17:07:54 2014 -0700
    responsible_merge_commit = $& if merge_info =~ /commit [0-9a-f]+/         # commit 1620f62b6849a911a5d61b514dc93d4654b6eee7

    if responsible_merge_commit
      puts "Branch #{simple_branch_name} exists, despite #{responsible_merge_party} merging it to master on #{responsible_merge_date} in #{responsible_merge_commit}."
    else
      puts "Branch #{simple_branch_name} exists, despite already being merged to master.  (Last Activity: #{last_updated_date})"
    end
  end
end

# Check for finished hotfixes (merged to production)
remote_hashes.each do |hash,branch|
  next unless branch.to_s.include?('refs/heads/hotfix')

  simple_branch_name = branch.sub('refs/heads/','')

  # Check for remote branches containing the hash, and see if origin/production is in the mix.
  merged_to_production = system("git branch --contains #{hash} -r 2>&1 | grep --quiet origin/production")

  if merged_to_production
    responsible_merge_party = 'An Unknown Entity'
    responsible_merge_date = 'An Unkonwn Date'
    responsible_merge_commit = nil

    last_updated_info = `git log -n 1 #{hash}`
    last_updated_date = "#{$1} #{$2}" if last_updated_info =~ /Date: +\S+\s+(\S+\s+\S+)\s+\S+\s+(\S+)/ # Date:   Thu Jul 24 17:07:54 2014 -0700

    # Try to determine who did it, and when.
    merge_info = `git log origin/production ^origin/#{simple_branch_name} --ancestry-path --merges | grep -B 5 "Merge branch '#{simple_branch_name}'"`

    responsible_merge_party  = $1 if merge_info =~ /Author: +([^<]+?) *</     # Author: Matthew McClure <mmcclure@brightcove.com>
    responsible_merge_date   = "#{$1} #{$2}" if merge_info =~ /Date: +\S+\s+(\S+\s+\S+)\s+\S+\s+(\S+)/ # Date:   Thu Jul 24 17:07:54 2014 -0700
    responsible_merge_commit = $& if merge_info =~ /commit [0-9a-f]+/         # commit 1620f62b6849a911a5d61b514dc93d4654b6eee7

    if responsible_merge_commit
      puts "Branch #{simple_branch_name} exists, despite #{responsible_merge_party} merging it to production on #{responsible_merge_date} in #{responsible_merge_commit}."
    else
      puts "Branch #{simple_branch_name} exists, despite already being merged to production.  (Last Activity: #{last_updated_date})"
    end
  end
end


