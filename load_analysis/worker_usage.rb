require 'rubygems'
require 'json'
require 'time'

module Stats
  def self.sum(a)
    a.inject(&:+)
  end

  def self.mean(a)
    sum(a) / a.length.to_f
  end

  def self.sample_variance(a)
    m = mean(a)
    sum = a.inject(0){ |accum, i| accum + (i - m) ** 2 }
    sum / (a.length - 1).to_f
  end

  def self.standard_deviation(a)
    Math.sqrt(sample_variance(a))
  end

  def self.pearson_correlation(x,y)
    raise "Cannot correlate differing-length lists!" unless x.length == y.length
    return 0 if x.length == 0

    x_mean = mean(x)
    x_stddev = standard_deviation(x)
    y_mean = mean(y)
    y_stddev = standard_deviation(y)

    score_x = x.map { |val| (val - x_mean) / x_stddev }
    score_y = y.map { |val| (val - y_mean) / y_stddev }

    sum = 0.0
    score_x.length.times { |i| sum += (score_x[i] * score_y[i]) }
    sum / (x.length - 1)
  end

  def self.analyze(values)
    v_sum = sum(values)
    v_mean = mean(values)
    v_count = values.length

    deviation = 0.0
    average_deviation = 0.0
    standard_deviation = 0.0
    variance = 0.0
    skew = 0.0
    kurtosis = 0.0
  
    values.each do |num|
      deviation = num - v_mean
      average_deviation += deviation.abs
      variance += deviation ** 2
      skew += deviation ** 3
      kurtosis += deviation ** 4
    end

    average_deviation /= v_count
    variance /= (v_count - 1)
    standard_deviation = Math.sqrt(variance)

    if variance > 0.0
      skew /= (v_count * variance * standard_deviation)
      kurtosis = kurtosis / (v_count * variance * variance) - 3.0
    end

    {
      count: v_count,
      sum: v_sum,
      mean: v_mean,
      stddev: standard_deviation,
      variance: variance,
      skew: skew,
      kurtosis: kurtosis
    }
  end

end

# Get worker usage data per-day, per-cloud.

# These are the gig-month prices.
EBS_GP2_PRICES = {
  "us-east-1" => 0.10,
  "eu-west-1" => 0.11,
  "us-west-2" => 0.10
}

ON_DEMAND_PRICES = {
  "c3.8xlarge"  => { 1 => 1.68, 3 => 1.912, 6 => 1.68, 13 => 1.68 },
  "cc2.8xlarge" => { 1 => 2.00, 3 => 2.25,  6 => 2.00, 13 => 2.00 },
  "c3.xlarge"  => { 13 => 0.21 }
}

# SPOT_PRICES = {}
# price_data = JSON.parse(File.read(File.join(File.dirname(__FILE__),'spot_pricing_nov.json')))
# price_data["SpotPriceHistory"].each do |h|
#   type = h["InstanceType"]
#   zone = h["AvailabilityZone"]
#   time = Time.parse(h["Timestamp"])
#   price = h["SpotPrice"].to_f
#
#   SPOT_PRICES[type] ||= Hash.new { |h,k| h[k] = [] }
#   SPOT_PRICES[type][zone] << [time.to_i, time, price]
# end
#
# # Make sure we've got the prices sorted by timestamp.
# SPOT_PRICES.keys.each { |type| SPOT_PRICES[type].keys.each { |zone| SPOT_PRICES[type][zone] = SPOT_PRICES[type][zone].sort_by { |time_i,time,price| time_i } } }

SPOT_PRICES = Hash.new { |h,day|
  h[day] = Hash.new { |h,cloud|
    h[cloud] = Hash.new { |h,type|
      h[type] = get_spot_price_history(day, cloud, type)
    }
  }
}

AWS_CREDS = JSON.parse(File.read(File.join(File.dirname(__FILE__),'creds.json')))

PULLED_SPOTS = {}
File.readlines(File.join(File.dirname(__FILE__),'pulled_spot_worker_ids.txt')).each { |sid| PULLED_SPOTS[sid.to_i] = true }


#############################################################

def get_spot_price_history(day, cloud_id, instance_type)
  cloud = Cloud.find(cloud_id)
  client = Aws::EC2::Client.new(region: cloud.service_region, access_key_id: AWS_CREDS['access_key_id'], secret_access_key: AWS_CREDS['secret_access_key'])

  prices = Hash.new { |h,k| h[k] = [] }

  puts "STATUS: Getting spot price history for #{day} #{cloud.service_region} #{instance_type}..."
  started_at = Time.now

  next_token = nil
  while next_token != ""
    puts "STATUS: ... making spot price call"
    response = client.describe_spot_price_history({
      start_time: Time.parse(day),
      end_time: Time.parse(day) + 24.hours,
      instance_types: [instance_type],
      product_descriptions: ['Linux/UNIX'],
      next_token: next_token
    })
    next_token = response.next_token

    response.spot_price_history.each do |h|
      prices[h.availability_zone] << [h.timestamp.to_i, h.spot_price.to_f]
    end
  end

  elapsed = Time.now - started_at
  puts "STATUS: Done getting spot price history (#{elapsed.round}s)"

  # Make sure the prices are in correct order.
  prices.keys.each { |zone| prices[zone] = prices[zone].sort_by { |time,price| time } }

  # puts "STATUS: SPOT PRICE INFO: #{prices.inspect}"

  prices
end

def log(message)
  now = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
  STDERR.puts "STATUS: #{now} #{message}"
end

def spot_price_for_time(cloud_id, type, zone, time)
  day = Time.at(time).strftime('%Y-%m-%d')
  prices = SPOT_PRICES[day][cloud_id][type][zone]

  if zone.blank?
    STDERR.puts "WARNING: Spot worker without availability zone; using zero for its price. #{type} at #{time}"
    return 0.0
  end

  raise "No price available for #{type} #{zone} #{time}" if prices.empty? || (time < prices.first[0])
  cur = 0
  cur += 1 while prices[cur+1] && (time >= prices[cur+1][0])
  prices[cur][1]
end

def load_available_machine_type(amt_id)
  amt = AvailableMachineType.find(amt_id)

  # If we need to support more EBS disk types than GP2, we'll need to get more pricing data in here.
  raise "Unknown root volume type for AMT #{amt_id}: #{amt.root_volume_type}" unless amt.root_volume_type == 'gp2'
  raise "Unknown EBS volume type for AMT #{amt_id}: #{amt.ebs_volume_type}" unless amt.ebs_volume_type == 'gp2' || (amt.use_ebs_volume == false)

  ebs_gig_month_price = EBS_GP2_PRICES[amt.cloud.service_region]
  raise "Unknown region for EBS pricing: #{amt.cloud.service_region}" unless ebs_gig_month_price

  if amt.use_ebs_volume
    ebs_total_size = amt.root_volume_size + (amt.ebs_volume_count * amt.ebs_volume_size)
  else
    ebs_total_size = amt.root_volume_size
  end
  ebs_hourly_price = (ebs_gig_month_price * ebs_total_size) / (24 * 30)

  on_demand_hourly_price = ON_DEMAND_PRICES[amt.machine_type.instance_type][amt.cloud_id] rescue nil
  raise "Unknown instance type / cloud combo for pricing: #{amt.machine_type.instance_type} in cloud #{amt.cloud_id}" unless on_demand_hourly_price

  {
    cloud_id: amt.cloud_id,
    ebs_price: ebs_hourly_price,
    max_load: amt.max_load,
    target_load: amt.target_load,
    instance_type: amt.machine_type.instance_type,
    on_demand_hourly_price: on_demand_hourly_price
  }
end

def cost_for_worker(worker, start, finish)
  amt = AVAILABLE_MACHINE_TYPES[worker[:amt_id]]

  # Figure out the starting point for billing in this day
  billing_start = worker[:launched].to_i
  billing_start += 3600 while billing_start < start

  # TODO: Adjust for what portion of a first/last billing hour was in this period.

  if worker[:lifecycle] == 'SPOT'
    cost_for_spot_instance(amt, worker[:availability_zone], billing_start, finish)
  else
    cost_for_on_demand_instance(amt, billing_start, finish)
  end
end

def cost_for_spot_instance(amt, az, billing_start, finish)
  cost = 0.0
  hours = 0
  while billing_start < finish
    cost += amt[:ebs_price] + spot_price_for_time(amt[:cloud_id], amt[:instance_type], az, billing_start)
    hours += 1
    billing_start += 3600
  end

  # This would happen if we only had the final half-hour of a billing hour during our
  # current billing period (the current day), for example.
  return [0,0] if hours == 0

  [cost, cost / hours]
end

def cost_for_on_demand_instance(amt, billing_start, finish)
  cost = 0.0
  hours = 0

  while billing_start < finish
    cost += amt[:ebs_price] + amt[:on_demand_hourly_price]
    hours += 1
    billing_start += 3600
  end

  # This would happen if we only had the final half-hour of a billing hour during our
  # current billing period (the current day), for example.
  return [0,0] if hours == 0

  [cost, cost / hours]
end

#############################################################

AVAILABLE_MACHINE_TYPES = Hash.new { |h,k| h[k] = load_available_machine_type(k) }
AVAILABILITY_ZONE_NAMES = AvailabilityZone.select("id,name").where(state: "active").all.map { |az| [az.id, az.name] }.to_h

def generate_daily_stats(cloud_id, day)
  report_row_data = []
  traffic_distribution = Hash.new(0.0)

  log "Generating report for cloud #{cloud_id}, #{day} ..."

  next_day = day + 24.hours

  log "  Loading workers..."
  workers = {}
  Worker.where(cloud_id: cloud_id).where("(killed_at is NULL AND state = 'active') OR killed_at >= ?", day).where("launched_at < ?", next_day).all.each do |w|
  # Worker.where(cloud_id: cloud_id).where("(killed_at is NULL AND state = 'active') OR killed_at >= ?", day).where("launched_at < ?", next_day).first(10).each do |w|
    workers[w.id] = { 
      worker: w,
      launched: w.launched_at,
      killed: w.killed_at,
      amt_id: w.available_machine_type_id,
      availability_zone: AVAILABILITY_ZONE_NAMES[w.availability_zone_id],
      lifecycle: w.spot? ? 'SPOT' : 'ON-DEMAND',
      events: Hash.new(0),
      minutes_processed: 0.0,
      pulled: PULLED_SPOTS[w.id] ? 'Y' : 'N'
    }
  end; nil

  log "  Loaded #{workers.size} workers..."

  total_output_count = 0
  worker_count = 0
  workers.each_pair do |wid, worker|
    worker_start = [day.to_i, worker[:launched].to_i].max
    worker_finish = [next_day.to_i, (worker[:killed] || next_day).to_i].min

    amt = AVAILABLE_MACHINE_TYPES[worker[:amt_id]]

    billable_minutes_processed = 0.0
    count = 0
    OutputMediaFile.where(worker_id: wid).select('id,estimated_transcode_load,potential_adjusted_duration_in_ms,ready_at,started_at,finished_at').each do |output|
      # puts output.inspect
      next unless (output.estimated_transcode_load && output.started_at && output.finished_at)
      # puts "Output #{output.id}"

      # Track the estimated_transcode_load we add as ready per-minute.
      traffic_distribution[(output.ready_at.to_i / 60) * 60] += output.estimated_transcode_load if output.ready_at

      # TODO: Adjust for what portion of the output was completed in this period.
      billable_minutes_processed += (output.potential_adjusted_duration_in_ms.to_i / 60_000.0)


      load = output.estimated_transcode_load.to_i
      start_seconds = output.started_at.to_i
      finish_seconds = output.finished_at.to_i
      # puts "  Start: #{start_seconds}"
      # puts "  Finish: #{finish_seconds}"
      next if finish_seconds < worker_start
      next if start_seconds > worker_finish
      # puts "   Load: #{load}"
      worker[:events][start_seconds] += load
      worker[:events][finish_seconds] -= load
      count += 1
    end; nil

    total_output_count += count

    total_max_capacity = (worker_finish - worker_start) * amt[:max_load]
    total_target_capacity = (worker_finish - worker_start) * amt[:target_load]

    previous_event_time = worker_start
    current_load = 0
    used_capacity = 0
    worker[:events].keys.sort.each do |event_time|
      value = worker[:events][event_time]
      if event_time <= worker_start
        current_load += value
      elsif event_time >= worker_finish
        duration = worker_finish - previous_event_time
        used_capacity += (duration * current_load)
        break
      else
        duration = event_time - previous_event_time
        used_capacity += (duration * current_load)
        previous_event_time = event_time
        current_load += value
      end
    end


  #   amt = {
  #     ebs_price: ebs_hourly_price,
  #     max_load: amt.max_load,
  #     target_load: amt.target_load,
  #     instance_type: amt.machine_type.instance_type,
  #     on_demand_hourly_price: on_demand_hourly_price
  #   }
  
  #     workers[w.id] = {
  #       worker: w,
  #       launched: w.launched_at,
  #       killed: w.killed_at,
  #       amt_id: w.available_machine_type_id,
  #       availability_zone: AVAILABILITY_ZONE_NAMES[w.availability_zone_id],
  #       lifecycle: w.spot? ? 'SPOT' : 'ON-DEMAND',
  #       events: Hash.new { |h,k| h[k] = 0 }
  #     }

    total_cost,avg_hourly_cost = cost_for_worker(worker, worker_start, worker_finish)

    # puts ['DATE', 'CLOUD_ID', 'WORKER_ID', 'INSTANCE_TYPE', 'LIFECYCLE', 'LAUNCHED', 'KILLED', 'PULLED', 'COST', 'HOURLY_COST', 'TARGET_LOAD', 'MAX_LOAD', 'TARGET_LOAD_SECONDS', 'MAX_LOAD_SECONDS', 'OUTPUT_COUNT', 'USED_LOAD_SECONDS', 'BILLABLE_MINUTES'].join("\t")

    clean_date = day.strftime('%Y-%m-%d')
    puts [clean_date, cloud_id, wid, amt[:instance_type], worker[:lifecycle], worker[:launched], worker[:killed], worker[:pulled], total_cost, avg_hourly_cost, amt[:target_load], amt[:max_load], total_target_capacity, total_max_capacity, count, used_capacity, billable_minutes_processed].join("\t")

    report_row_data << {
      worker_id: wid,
      instance_type: amt[:instance_type],
      lifecycle: worker[:lifecycle],
      pulled: worker[:pulled],
      total_cost: total_cost,
      hourly_cost: avg_hourly_cost,
      target_load_seconds: total_target_capacity,
      max_load_seconds: total_max_capacity,
      used_load_seconds: used_capacity,
      output_count: count,
      billable_minutes: billable_minutes_processed
    }

    worker_count += 1
    if (worker_count % 100) == 0
      log "    Processed #{worker_count} workers..."
    end
  end

  log "  Total outputs for day: #{total_output_count}"

  return {
    row_data: report_row_data,
    traffic_distribution: traffic_distribution
  }
end

def generate_summary(cloud_id, day, data)
  worker_row_data = data[:row_data]
  traffic_distribution = data[:traffic_distribution]

  traffic_stats = Stats.analyze(traffic_distribution.values)

  # worker_row_data << {
  #   worker_id: wid,
  #   instance_type: amt[:instance_type],
  #   lifecycle: worker[:lifecycle],
  #   total_cost: total_cost,
  #   hourly_cost: avg_hourly_cost,
  #   target_load_seconds: total_target_capacity,
  #   max_load_seconds: total_max_capacity,
  #   used_load_seconds: used_capacity,
  #   output_count: count,
  #   billable_minutes: billable_minutes_processed
  # }

  # summarize:
  #  cost for day (total, and by instance/spot type)
  #  capacity for day (target/max)
  #  usage for day
  #  usage efficiency (target/max)
  #  billable minutes
  #  cost per minute
  #  output count ???
  #  cost per output ???
  #  avg hourly worker cost
  #  worker count ???
  #  spot vs. on-demand usage (and efficiency?)
  #  Pulled spots info/counts?

  summary = {
    total_cost: 0.0,
    billable_minutes: 0.0,
    output_count: 0,
    worker_count: 0,
    pulled_spot_count: 0,

    total_hourly_cost: 0.0,
    workers_with_cost_count: 0, # Count how many workers we have cost data for, so we can make our averages accurate.

    max_seconds: 0,
    target_seconds: 0,
    used_seconds: 0,

    spot_worker_count: 0,
    spot_cost: 0.0,
    spot_max_seconds: 0,
    spot_target_seconds: 0,
    spot_used_seconds: 0,
    spot_total_hourly_cost: 0.0,
    spot_workers_with_cost_count: 0,

    on_demand_worker_count: 0,
    on_demand_cost: 0.0,
    on_demand_max_seconds: 0,
    on_demand_target_seconds: 0,
    on_demand_used_seconds: 0,
    on_demand_total_hourly_cost: 0.0,
    on_demand_workers_with_cost_count: 0
  }

  worker_row_data.each do |w|
    summary[:total_cost] += w[:total_cost]
    summary[:billable_minutes] += w[:billable_minutes]
    summary[:output_count] += w[:output_count]
    summary[:pulled_spot_count] += 1 if w[:pulled] == 'Y'
    summary[:total_hourly_cost] += w[:hourly_cost]
    summary[:workers_with_cost_count] += 1 if w[:hourly_cost] > 0.0
    summary[:worker_count] += 1

    summary[:max_seconds] += w[:max_load_seconds]
    summary[:target_seconds] += w[:target_load_seconds]
    summary[:used_seconds] += w[:used_load_seconds]

    if w[:lifecycle] == 'SPOT'
      summary[:spot_worker_count] += 1
      summary[:spot_cost] += w[:total_cost]
      summary[:spot_max_seconds] += w[:max_load_seconds]
      summary[:spot_target_seconds] += w[:target_load_seconds]
      summary[:spot_used_seconds] += w[:used_load_seconds]
      summary[:spot_total_hourly_cost] += w[:hourly_cost]
      summary[:spot_workers_with_cost_count] += 1 if w[:hourly_cost] > 0.0
    else
      summary[:on_demand_worker_count] += 1
      summary[:on_demand_cost] += w[:total_cost]
      summary[:on_demand_max_seconds] += w[:max_load_seconds]
      summary[:on_demand_target_seconds] += w[:target_load_seconds]
      summary[:on_demand_used_seconds] += w[:used_load_seconds]
      summary[:on_demand_total_hourly_cost] += w[:hourly_cost]
      summary[:on_demand_workers_with_cost_count] += 1 if w[:hourly_cost] > 0.0
    end

  end

  summary[:cost_per_minute] = summary[:total_cost] / summary[:billable_minutes] rescue 0.0
  summary[:cost_per_output] = summary[:total_cost] / summary[:output_count] rescue 0.0

  summary[:avg_hourly_cost] = summary[:total_hourly_cost] / summary[:workers_with_cost_count] rescue 0.0
  summary[:spot_avg_hourly_cost] = summary[:spot_total_hourly_cost] / summary[:spot_workers_with_cost_count] rescue 0.0
  summary[:on_demand_avg_hourly_cost] = summary[:on_demand_total_hourly_cost] / summary[:on_demand_workers_with_cost_count] rescue 0.0

  summary[:max_usage_pct] = 100.0 * summary[:used_seconds] / summary[:max_seconds]
  summary[:target_usage_pct] = 100.0 * summary[:used_seconds] / summary[:target_seconds]
  summary[:spot_max_usage_pct] = 100.0 * summary[:spot_used_seconds] / summary[:spot_max_seconds]
  summary[:spot_target_usage_pct] = 100.0 * summary[:spot_used_seconds] / summary[:spot_target_seconds]
  summary[:on_demand_max_usage_pct] = 100.0 * summary[:on_demand_used_seconds] / summary[:on_demand_max_seconds]
  summary[:on_demand_target_usage_pct] = 100.0 * summary[:on_demand_used_seconds] / summary[:on_demand_target_seconds]

  summary[:traffic_sum] = traffic_stats[:sum]
  summary[:traffic_avg] = traffic_stats[:mean]
  summary[:traffic_stddev] = traffic_stats[:stddev]
  summary[:traffic_spikiness] = traffic_stats[:kurtosis]

  clean_date = day.strftime('%Y-%m-%d')

  puts "SUMMARY: #{clean_date}\t#{cloud_id}\t" + summary.keys.map { |k| "#{k}=#{summary[k]}" }.join(", ")

  summary
end


#############################################################

def run_report(cloud_id, first_day_string, last_day_string)
  first_day = DateTime.parse(first_day_string)
  last_day  = DateTime.parse(last_day_string)

  current_day = first_day
  while current_day <= last_day
    report_data = generate_daily_stats(cloud_id, current_day)

    generate_summary(cloud_id, current_day, report_data)

    current_day += 24.hours
  end
end


#############################################################
#############################################################


# PRICING:

# Cloud 1, cc2.8xlarge = 2.00
# Cloud 1, c3.8xlarge  = 1.68

# Cloud 3, cc2.8xlarge = 2.25
# Cloud 3, c3.8xlarge  = 1.912

# Cloud 6, cc2.8xlarge = 2.00
# Cloud 6, c3.8xlarge  = 1.68


# EBS PRICING

# Cloud 1: 0.10 per gig-month, 1034 gigs = 103.40/month? = 0.143611111 per hour
# Cloud 3: 0.11 per gig-month, 1034 gigs = 113.74/month? = 0.157972222 per hour
# Cloud 6: 0.10 per gig-month, 1034 gigs = 103.40/month? = 0.143611111 per hour


#############################################################
#############################################################



# For now only do this for a few main clouds - us-east, eu-dublin, and us-oregon

Worker.logger.level = 10
OutputMediaFile.logger.level = 10

# cloud_list = [1,3,6]
cloud_list = [1,13]
first_day = '2016-11-22'
last_day = '2016-11-27'

puts ['DATE', 'CLOUD_ID', 'WORKER_ID', 'INSTANCE_TYPE', 'LIFECYCLE', 'LAUNCHED', 'KILLED', 'PULLED', 'COST', 'HOURLY_COST', 'TARGET_LOAD', 'MAX_LOAD', 'TARGET_LOAD_SECONDS', 'MAX_LOAD_SECONDS', 'OUTPUT_COUNT', 'USED_LOAD_SECONDS', 'BILLABLE_MINUTES'].join("\t")

cloud_list.each do |cloud_id|
  run_report(cloud_id, first_day, last_day)
end; nil

