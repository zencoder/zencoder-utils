#
# Setting Grid class, used to create a grid of valid settings (including ranges), and
# then filter them to determine what combinations of options are valid.
#
# Initialize with a list of keys for the settings, and optionally an interval to be used on float ranges.
# Then add any valid settings hashes (will automatically permute arrays, and include ranges).
#
# At that point, the filtering is available for use:
#
#   filter_reject(key,value) - remove ocurrances of value from key (value can be array/range)
#   filter_only(key,value) - remove occurrances from key that don't mach value (value can be array/range)
#   choose(key, value) - keep only the specific value for the key
#
#   reset_filters - revert any filtering so the grid can be re-used
#
#   options_for(key) - get a list of all valid options for the key (may include ranges)
#   valid?(key, value) - check if the value is a valid option for the key
#   min(key) - get the minimum valid value for key (numeric/string only)
#   max(key) - get the maximum valid value for key (numeric/string only)
#   nearest(key, value) - get the valid value for key nearest to the specified value (numeric/string only)
#   mid(key) - get the valid value for key nearest the average of min and max  (numeric only)
#

module ZenEngine
  class SettingsGrid
    attr_accessor :settings_grid, :float_interval
    attr_reader :keys

    # Keys should be an array of expected hash keys in the grid.  The float_interval says how far
    # ranges should be adjusted away from excluded values.
    def initialize(keys, float_interval = 0.01)
      @keys = keys
      @settings_grid = []
      @float_interval = float_interval
    end

    # Add a new permutation of options, such as:
    #   { :profile => 'he-aac', :sample_rate => [11025,22050,44100,48000], :quality => 0.22..0.78 }
    #   Note: this resets filters
    def add(settings_hash)
      base_settings = {}
      permute_settings = {}
      settings_hash.each_pair do |k,v|
        if v.kind_of?(Array)
          permute_settings[k] = v
        else
          base_settings[k] = v
        end
      end

      permute_hash_set(base_settings, permute_settings) do |permuted_set|
        # Could be optimized by updating ranges of existing rows when applicable and safe.
        add_single(permuted_set) unless matching_set(permuted_set)
      end
      
      reset_filters # Can't predict the filters after adding new rows, so reset.
    end
    alias_method :<<, :add

    # Merge with another grid, producing a new grid that's the intersection of the two.
    # Keys must match, but float_interval with be the lesser of the two.
    def merge(other_grid)
      raise "SettingsGrid merging only allowed when keys match." unless ((@keys - other_grid.keys) + (other_grid.keys - @keys)).empty?
      new_grid = self.class.new(@keys, [@float_interval, other_grid.float_interval].min)
      other_grid.settings_grid.each do |other_row|
        matching_sets(other_row).each do |local_row|
          new_hash = dupe_settings_hash(local_row)
          @keys.each do |key|
            if local_row[key].kind_of?(Range)
              new_hash[key] = update_range_inclusion(local_row[key], other_row[key])
            elsif other_row[key].kind_of?(Range)
              new_hash[key] = update_range_inclusion(other_row[key], local_row[key])
            end
          end
          new_grid << new_hash
        end
      end
      new_grid
    end

    # Reset any filtering back to the full grid.
    def reset_filters
      @temp_grid = nil
    end
    
    # Save any applied filters to the main settings, so a reset now goes back to the current filter set.
    def apply_filters
      if @temp_grid
        @settings_grid = @temp_grid
        @temp_grid = nil
      end
    end

    def filter_reject(key, value)
      # Small helper method so we can correctly handle arrays too.
      if value.kind_of?(Array)
        value.each { |v| filter_reject_single_value(key, v) }
      else
        filter_reject_single_value(key, value)
      end
    end

    def filter_reject_single_value(key, value)
      cur_line = 0
      total_lines = temp_grid.size
      while cur_line < total_lines
        grid_set = temp_grid[cur_line]

        if set_matches_value(grid_set, key, value)
          if grid_set[key].kind_of?(Range)
            updated_range = update_range_exclusion(grid_set[key], value)

            if updated_range.nil?
              temp_grid.delete_at(cur_line)
              total_lines -= 1

            elsif updated_range.kind_of?(Array)
              # We had to split the range into two...
              secondary = dupe_settings_hash(grid_set)
              temp_grid[cur_line][key] = updated_range.first
              secondary[key] = updated_range.last
              temp_grid << secondary
              cur_line += 1
            else
              temp_grid[cur_line][key] = updated_range
              cur_line += 1
            end
          else
            temp_grid.delete_at(cur_line)
            total_lines -= 1
          end
        else
          cur_line += 1
        end
      end
    end

    def filter_only(key, value)
      cur_line = 0
      total_lines = temp_grid.size
      while cur_line < total_lines
        grid_set = temp_grid[cur_line]

        if set_matches_value(grid_set, key, value)
          if grid_set[key].kind_of?(Range)
            updated_range = update_range_inclusion(grid_set[key], value)

            if updated_range.kind_of?(Array)
              # Replace existing range with the new array.
              temp_grid.delete_at(cur_line)
              total_lines -= 1
              
              updated_range.each do |new_range|
                new_hash = dupe_settings_hash(grid_set)
                new_hash[key] = new_range
                temp_grid << new_hash
              end
              
            else
              # Update and move to the next.
              temp_grid[cur_line][key] = updated_range
              cur_line += 1
            end
          else
            # Leave it as is, and move to the next.
            cur_line += 1
          end
        else
          temp_grid.delete_at(cur_line)
          total_lines -= 1
        end
      end
    end

    # Choose the specific value for the key, and return a boolean of whether it was a valid choice.
    def choose(key, value)
      raise "Choosing a range is invalid" if value.kind_of?(Range)
      filter_only(key, value)
      return valid?(key, value)
    end

    def options_for(key)
      temp_grid.collect { |s| s[key] }.sort_by { |v| v.kind_of?(Range) ? v.first : v }.uniq
    end

    def max(key)
      temp_grid.collect { |s| s[key].kind_of?(Range) ? s[key].last : s[key] }.sort.last
    end

    def min(key)
      temp_grid.collect { |s| s[key].kind_of?(Range) ? s[key].first : s[key] }.sort.first
    end

    def mid(key) # Only valid for numeric options.
      nearest(key, min(key) + max(key) / 2)
    end

    def nearest(key, value) # Only valid for numeric options
      valid_options = options_for(key)
      return nil if valid_options.empty?
      return value if valid_options.any? { |o| o == value || (o.respond_to?(:include?) && o.include?(value)) }
      valid_options = valid_options.collect { |o| o.kind_of?(Range) ? [o.first,o.last] : o }.flatten.sort
      return valid_options.first if valid_options.first > value
      return valid_options.last if valid_options.last < value

      valid_options.each_index do |i|
        lower_bound = valid_options[i]
        upper_bound = valid_options[i + 1] || 0
        next if value > upper_bound
        midpoint = (lower_bound + upper_bound) / 2.0
        return lower_bound if value <= midpoint
        return upper_bound
      end

      nil
    end

    def valid?(key, value) # Check if a value is valid for a key
      options_for(key).any? { |o| o == value || (o.respond_to?(:include?) && o.include?(value)) }
    end


    # DEBUG HELPERS

    def settings_dump
      puts @keys.join(',').upcase
      @settings_grid.sort_by { |s| a = []; @keys.each { |k| a << (s[k].kind_of?(Range) ? s[k].first : s[k]) }; a }.each do |settings|
        puts @keys.map { |k| settings[k] }.join(',')
      end
    end

    def filter_dump
      puts @keys.join(',').upcase
      temp_grid.sort_by { |s| a = []; @keys.each { |k| a << (s[k].kind_of?(Range) ? s[k].first : s[k]) }; a }.each do |settings|
        puts @keys.map { |k| settings[k] }.join(',')
      end
    end

    def temp_grid
      return @temp_grid if @temp_grid
      @temp_grid = []
      @settings_grid.each do |settings|
        @temp_grid << dupe_settings_hash(settings)
      end
      @temp_grid
    end


    private

    def matching_set(settings)
      @settings_grid.each do |grid_settings|
        return grid_settings if @keys.all? { |k| set_matches_value(grid_settings, k, settings[k]) }
      end
      nil
    end

    def matching_sets(settings)
      @settings_grid.select { |grid_settings| @keys.all? { |k| set_matches_value(grid_settings, k, settings[k]) } }
    end

    def set_matches_value(grid_set, key, value)
      set_value = grid_set[key]
      if set_value.kind_of?(Range)
        if value.kind_of?(Array)
          value.any? { |v| set_value.include?(v) }
        elsif value.kind_of?(Range)
          set_value.include?(value.first) || value.include?(set_value.first) # Test for overlap
        else
          set_value.include?(value)
        end
      elsif value.kind_of?(Range) || value.kind_of?(Array)
        value.include?(set_value)
      else
        set_value == value
      end
    end

    # Exclude a value from the range.  Value may be number or range, but NOT an array.
    def update_range_exclusion(range, value)
      if value.kind_of?(Range)
        value_first = value.first
        value_last = value.last
      else
        value_first = value
        value_last = value
      end

      new_ranges = []

      if range.include?(value_first) && value_first > range.first
        new_last = value_first
        if new_last.kind_of?(Float) || range.first.kind_of?(Float)
          new_ranges << ((range.first) .. (new_last - @float_interval))
        else
          new_ranges << ((range.first) .. (new_last - 1))
        end
      end

      if range.include?(value_last) && value_last < range.last
        new_first = value_last
        if new_first.kind_of?(Float) || range.last.kind_of?(Float)
          new_ranges << ((new_first + @float_interval) .. (range.last))
        else
          new_ranges << ((new_first + 1) .. (range.last))
        end
      end

      new_ranges.delete_if { |r| r.first > r.last }

      return nil if new_ranges.empty?
      return new_ranges.first if new_ranges.length == 1
      return new_ranges # Had to split into two ranges.
    end

    # Intersect the range with the specified value.  Value may be number, range, or array.
    def update_range_inclusion(range, value)
      if value.kind_of?(Range)

        low = [range.first, value.first].max
        high = [range.last, value.last].min

        # Make all floats if any were floats.
        if (range.first+range.last+value.first+value.last).kind_of?(Float)
          low = low.to_f
          high = high.to_f
        end

        if low == high
          low # Simplify if only one value is left
        else
          low .. high
        end
      elsif value.kind_of?(Array)
        value.select { |v| range.include?(v) }
      else
        value
      end
    end

    def add_single(settings)
      @settings_grid << dupe_settings_hash(settings)
    end

    # Create a dupe of a settings hash, so messing with it later won't affect the original.
    def dupe_settings_hash(settings)
      @keys.inject({}) { |a,k| a[k] = settings[k].kind_of?(Numeric) ? settings[k] : settings[k].dup; a }
    end

    # Run through a hash and run the given block on each permutation of options.
    def permute_hash_set(init, options, &block)
      if options.keys.length < 1
        block.call(init)
      else
        more_options = options.dup
        pk,pv = more_options.shift
        pv.each { |v| permute_hash_set(init.merge(pk => v), more_options, &block) }
      end
    end

  end # class
end # module
