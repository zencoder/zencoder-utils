#!/bin/sh
cd /data/zencoder/current
bundle exec ruby ./script/runner -e 'production' /data/zencoder/fix_stuck_jobs.rb
#bundle exec ruby ./script/runner -e 'production' 'Worker.find_all_by_state("problematic").each{|w| w.terminate! rescue true }'

