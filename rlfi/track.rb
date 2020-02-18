require "gosu"
require "ruby-audio"
require_relative "rms"
require_relative "slider"
require_relative "speed"
require_relative "delay"

class Track
  attr_reader :buffer, :selection_buffer, :modified_selection_buffer, :sample_rate, :channels, :format,
              :filepath, :filename

  attr_accessor :y, :height
  
  TRACK_HEIGHT = 40

  def initialize filepath, x, y, width, height, prime = false, tag = nil
    @filepath = filepath
    @filename = filepath.split("/").last
    @x = x
    @y = y
    @height = height
    @width = width
    @selecting = false
    @prime = prime
    @tag = tag

    reset_effects

    @effect_width = width / 10

    x = @x - 20

    @speed_text = Gosu::Image.from_text "spd", 16
    @speed_slider = Slider.new x + @effect_width, @y + TRACK_HEIGHT, @effect_width, 0, 2, @speed
    @speed_slider.on_change do |value|
      if @speed > 0
        @speed = value
        process_effects
      end
    end

    @delay_text = Gosu::Image.from_text "dly", 16
    @delay_slider = Slider.new x + @effect_width * 3, @y + TRACK_HEIGHT, @effect_width, 0, 3, @delay
    @delay_slider.on_change do |value|
      @delay = value
      process_effects
    end

    @decay_text = Gosu::Image.from_text "dcy", 16
    @decay_slider = Slider.new x + @effect_width * 5, @y + TRACK_HEIGHT, @effect_width, 0, 3, @decay
    @decay_slider.on_change do |value|
      @decay = value
      process_effects
    end

    @limit_text = Gosu::Image.from_text "lmt", 16
    @limit_slider = Slider.new x + @effect_width * 7, @y + TRACK_HEIGHT, @effect_width, 0, 4, @limit, true
    @limit_slider.on_change do |value|
      @limit = value
      # process_effects
    end

    @volume_text = Gosu::Image.from_text "vol", 16
    @volume_slider = Slider.new x + @effect_width * 9, @y + TRACK_HEIGHT, @effect_width, 0, 2, @volume
    @volume_slider.on_change do |value|
      @volume = value
      # process_effects
    end

    @covers_text = Gosu::Image.from_text "selection contains x measures", 16
    @covers_slider = Slider.new x + @covers_text.width + 20, @y + TRACK_HEIGHT * 2, 100, 1, 8, 1, true, true

    @subelements = [@speed_slider, @delay_slider, @decay_slider, @limit_slider, @volume_slider]
  end

  def y= new_y
    @y = new_y
    @subelements.each { |elem| elem.y = @y + TRACK_HEIGHT }
    @covers_slider.y = @y + TRACK_HEIGHT * 2
  end

  def prime= is_prime
    @prime = !!is_prime

    if @prime
      @height = TRACK_HEIGHT * 3
      @subelements.push @covers_slider
    else
      @height = TRACK_HEIGHT * 2
      @subelements.delete @covers_slider
    end
  end

  def reset_effects
    @speed = 1.0
    @delay = 0.0
    @decay = 0.0
    @limit = 0
    @volume = 1.0
  end

  def on_change &block
    @callback = block
  end

  def process_effects
    unless @selection_buffer
      @modified_selection_buffer = nil
      return
    end

    @modified_selection_buffer = @selection_buffer.dup

    if @speed > 0 && @speed != 1
      @modified_selection_buffer =
        Speed.new(@speed).apply @modified_selection_buffer, @sample_rate, @channels
    end

    if @delay > 0 && @decay > 0
      @modified_selection_buffer =
        Delay.new(@delay, @decay).apply @modified_selection_buffer, @sample_rate, @channels
    end

    @callback.call @modified_selection_buffer if @callback
  end

  def contains? x, y
    @x <= x && @x + @width >= x && @y <= y && @y + @height >= y
  end

  def mouse_down x, y
    if x >= @x && x <= @x + @width && y >= @y && y <= @y + TRACK_HEIGHT
      @selecting = true
      @start_x = x
    elsif @subelement = @subelements.find { |e| e.contains? x, y }
      @subelement.mouse_down x, y
    end
  end

  def mouse_up x, y
    if @selecting && @start_x && @select_x
      @selecting = false

      if @select_x <= @start_x
        @start_x, @select_x, @selection_buffer = nil, nil, nil
        process_effects
      else
        buffer_count = @buffer.count
        start_index = (((@start_x - @x) / @width) * buffer_count).to_i
        end_index = ((@select_x - @x) / @width * buffer_count).to_i
        @selection_buffer = RubyAudio::Buffer.float end_index - start_index + 1, @channels
        (start_index..end_index).each.with_index { |i,j| @selection_buffer[j] = @buffer[i] }
        process_effects
      end
    elsif @subelement
      @subelement.mouse_up x, y
      @subelement = nil
    end
  end

  def mouse_update x, y
    if @selecting
      @select_x = x
    elsif @subelement
      @subelement.mouse_update x, y
    end
  end

  def read
    RubyAudio::Sound.open @filepath do |sound|
      @channels = 1
      @sample_rate = sound.info.samplerate
      @format = sound.info.format
      @buffer = RubyAudio::Buffer.float sound.info.frames, @channels
      sound.read @buffer
    end

    @buffer
  end

  def rms
    @rms ||= begin
      return [] unless @buffer
      rms = RMS.new @width
      rms.apply @buffer, @sample_rate, @channels
    end 
  end

  def draw
    if @start_x && @select_x && @select_x - @start_x > 0
      Gosu::draw_rect @start_x, @y, @select_x - @start_x, 40, Gosu::Color::GRAY
    end

		h = TRACK_HEIGHT / 2
    rms.each.with_index do |r, i|
      max = r[1] * h
      min = r[2].abs * h
      rms = r[0] * h
      Gosu::draw_rect @x + i, @y + h - max, 1, max, Gosu::Color::BLUE
      Gosu::draw_rect @x + i, @y + h, 1, min, Gosu::Color::BLUE
      Gosu::draw_rect @x + i, @y + h - rms, 1, rms * 2, Gosu::Color::GREEN
    end

    y = @y + TRACK_HEIGHT

    # x, y, z, scale_x, scale_y, color
    @speed_text.draw @x, y, 1, 1, 1, Gosu::Color::BLACK
    @delay_text.draw @x + @effect_width * 2, y, 1, 1, 1, Gosu::Color::BLACK
    @decay_text.draw @x + @effect_width * 4, y, 1, 1, 1, Gosu::Color::BLACK
    @limit_text.draw @x + @effect_width * 6, y, 1, 1, 1, Gosu::Color::BLACK
    @volume_text.draw @x + @effect_width * 8, y, 1, 1, 1, Gosu::Color::BLACK
    @covers_text.draw @x, y + TRACK_HEIGHT, 1, 1, 1, Gosu::Color::BLACK if @prime

    @speed_slider.draw
    @delay_slider.draw
    @decay_slider.draw
    @limit_slider.draw
    @volume_slider.draw
    @covers_slider.draw if @prime
  end
end
