require 'minitest/autorun'
require 'yaji'
require 'curb'

class TestParser < MiniTest::Unit::TestCase
  class Generator
    def initialize(data, options = {})
      @callback = nil
      @options = {:chunk_size => 10}.merge(options)
      @chunks = case data
                when Array
                  data
                when String
                  count = (data.bytesize / @options[:chunk_size].to_f).ceil
                  data.unpack("a#{@options[:chunk_size]}" * count)
                end
    end

    def on_body
      old = @callback
      @callback = Proc.new if block_given?
      old
    end

    def perform
      size = @options[:chunk_size]
      if @callback
        @chunks.each do |chunk|
          @callback.call(chunk)
        end
      end
    end
  end

  def test_it_generates_events
    events = []
    parser = YAJI::Parser.new(toys_json_str)
    parser.parse do |p, e, v|
      events << [p, e, v]
    end
    expected = [
      ['',                       :start_hash,  nil],
      ['',                       :hash_key,    'total_rows'],
      ['/total_rows',            :number,      2],
      ['',                       :hash_key,    'rows'],
      ['/rows',                  :start_array, nil],
      ['/rows/',                 :start_hash,  nil],
      ['/rows/',                 :hash_key,    'id'],
      ['/rows//id',              :string,      'buzz'],
      ['/rows/',                 :hash_key,    'props'],
      ['/rows//props',           :start_hash,  nil],
      ['/rows//props',           :hash_key,    'humanoid'],
      ['/rows//props/humanoid',  :boolean,     true],
      ['/rows//props',           :hash_key,    'armed'],
      ['/rows//props/armed',     :boolean,     true],
      ['/rows//props',           :end_hash,    nil],
      ['/rows/',                 :hash_key,    'movies'],
      ['/rows//movies',          :start_array, nil],
      ['/rows//movies/',         :number,      1],
      ['/rows//movies/',         :number,      2],
      ['/rows//movies/',         :number,      3],
      ['/rows//movies',          :end_array,   nil],
      ['/rows/',                 :end_hash,    nil],
      ['/rows/',                 :start_hash,  nil],
      ['/rows/',                 :hash_key,    'id'],
      ['/rows//id',              :string,      'barbie'],
      ['/rows/',                 :hash_key,    'props'],
      ['/rows//props',           :start_hash,  nil],
      ['/rows//props',           :hash_key,    'humanoid'],
      ['/rows//props/humanoid',  :boolean,     true],
      ['/rows//props',           :hash_key,    'armed'],
      ['/rows//props/armed',     :boolean,     false],
      ['/rows//props',           :end_hash,    nil],
      ['/rows/',                 :hash_key,    'movies'],
      ['/rows//movies',          :start_array, nil],
      ['/rows//movies/',         :number,      2],
      ['/rows//movies/',         :number,      3],
      ['/rows//movies',          :end_array,   nil],
      ['/rows/',                 :end_hash,    nil],
      ['/rows',                  :end_array,   nil],
      ['',                       :end_hash,    nil]
    ]
    assert_equal expected, events
  end

  def test_it_yields_enumerator
    parser = YAJI::Parser.new('{"hello":"world"}')
    e = parser.parse
    assert_equal ['', :start_hash, nil], e.next
    assert_equal ['', :hash_key, 'hello'], e.next
    assert_equal ['/hello', :string, 'world'], e.next
    assert_equal ['', :end_hash, nil], e.next
    assert_raises(StopIteration) { e.next }
  end

  def test_it_symbolizes_keys
    parser = YAJI::Parser.new('{"hello":"world"}', :symbolize_keys => true)
    e = parser.parse
    expected = [
      ['', :start_hash, nil],
      ['', :hash_key, :hello],
      ['/hello', :string, 'world'],
      ['', :end_hash, nil]
    ]
    assert_equal expected, e.to_a
  end

  def test_it_build_ruby_objects
    parser = YAJI::Parser.new(toys_json_str)
    objects = []
    parser.each do |o|
      objects << o
    end
    expected = [{'total_rows' => 2,
                 'rows' => [
                   {
                     'id' => 'buzz',
                     'props' => {'humanoid' => true, 'armed' => true},
                     'movies' => [1, 2, 3]
                   },
                   {
                     'id' => 'barbie',
                     'props' => {'humanoid' => true, 'armed' => false},
                     'movies' => [2, 3]
                   }
                 ]}]
    assert_equal expected, objects
  end

  def test_it_yields_whole_array
    parser = YAJI::Parser.new(toys_json_str)
    objects = []
    parser.each('/rows') do |o|
      objects << o
    end
    expected = [
      [
        {
          'id' => 'buzz',
          'props' => {'humanoid' => true, 'armed' => true},
          'movies' => [1, 2, 3]
        },
        {
          'id' => 'barbie',
          'props' => {'humanoid' => true, 'armed' => false},
          'movies' => [2, 3]
        }
      ]
    ]
    assert_equal expected, objects
  end

  def test_it_yeilds_array_contents_row_by_row
    parser = YAJI::Parser.new(toys_json_str)
    objects = []
    parser.each('/rows/') do |o|
      objects << o
    end
    expected = [
      {
        'id' => 'buzz',
        'props' => {'humanoid' => true, 'armed' => true},
        'movies' => [1, 2, 3]
      },
      {
        'id' => 'barbie',
        'props' => {'humanoid' => true, 'armed' => false},
        'movies' => [2, 3]
      }
    ]
    assert_equal expected, objects
  end

  def test_it_could_curb_async_approach
    curl = Curl::Easy.new('https://avsej.net/test.json')
    parser = YAJI::Parser.new(curl)
    object = parser.each.to_a.first
    expected = {'foo' => 'bar', 'baz' => {'nums' => [42, 3.1415]}}
    assert_equal expected, object
  end

  def test_it_allow_several_selectors
    parser = YAJI::Parser.new(toys_json_str)
    objects = []
    parser.each(['/total_rows', '/rows/']) do |o|
      objects << o
    end
    expected = [
      2,
      {
        'id' => 'buzz',
        'props' => {'humanoid' => true, 'armed' => true},
        'movies' => [1, 2, 3]
      },
      {
        'id' => 'barbie',
        'props' => {'humanoid' => true, 'armed' => false},
        'movies' => [2, 3]
      }
    ]
    assert_equal expected, objects
  end

  def test_it_optionally_yields_object_path
    parser = YAJI::Parser.new(toys_json_str)
    objects = []
    parser.each(['/total_rows', '/rows/'], :with_path => true) do |o|
      objects << o
    end
    expected = [
      ['/total_rows', 2],
      [
        '/rows/',
        {
          'id' => 'buzz',
          'props' => {'humanoid' => true, 'armed' => true},
          'movies' => [1, 2, 3]
        }
      ],
      [
        '/rows/',
        {
          'id' => 'barbie',
          'props' => {'humanoid' => true, 'armed' => false},
          'movies' => [2, 3]
        }
      ]
    ]
    assert_equal expected, objects
  end

  def test_it_allows_to_specify_filter_and_options_at_initialization
    parser = YAJI::Parser.new(toys_json_str,
                              :filter => ['/total_rows', '/rows/'],
                              :with_path => true)
    objects = []
    parser.each do |o|
      objects << o
    end
    expected = [
      ['/total_rows', 2],
      [
        '/rows/',
        {
          'id' => 'buzz',
          'props' => {'humanoid' => true, 'armed' => true},
          'movies' => [1, 2, 3]
        }
      ],
      [
        '/rows/',
        {
          'id' => 'barbie',
          'props' => {'humanoid' => true, 'armed' => false},
          'movies' => [2, 3]
        }
      ]
    ]
    assert_equal expected, objects
  end

  def test_it_doesnt_raise_exception_on_empty_input
    YAJI::Parser.new('').parse
    YAJI::Parser.new('  ').parse
    YAJI::Parser.new("\n").parse
    YAJI::Parser.new(" \n\n ").parse
  end

  def test_it_allows_to_create_parser_without_input
    YAJI::Parser.new
    YAJI::Parser.new(:filter => 'test')
    YAJI::Parser.new(:with_path => true)
  end

  def test_it_raises_argument_error_for_parser_without_input
    parser = YAJI::Parser.new
    assert_raises(ArgumentError) do
      parser.parse
    end
    assert_raises(ArgumentError) do
      parser.each { |_x| }
    end
  end

  def test_it_raises_argument_error_on_write_without_callback_set_up
    parser = YAJI::Parser.new
    assert_raises(ArgumentError) do
      parser.write('{"hello":"world"}')
    end
  end

  def test_it_allows_to_feed_the_data_on_the_fly
    parser = YAJI::Parser.new(:filter => '/rows/')

    objects = []
    parser.on_object do |obj|
      objects << obj
    end

    parser.write(<<-JSON)
      {
        "total_rows": 2,
        "rows": [
          {
    JSON
    parser.write(<<-JSON)
            "id": "buzz",
            "props": {
              "humanoid": true,
              "armed": true
            },
            "movies": [1,2,3]
          },
    JSON
    data = <<-JSON
          {
            "id": "barbie",
            "props": {
              "humanoid": true,
              "armed": false
            },
            "movies": [2,3]
          }
        ]
      }
    JSON
    parser << data

    expected = [
      {
        'id' => 'buzz',
        'props' => {'humanoid' => true, 'armed' => true},
        'movies' => [1, 2, 3]
      },
      {
        'id' => 'barbie',
        'props' => {'humanoid' => true, 'armed' => false},
        'movies' => [2, 3]
      }
    ]
    assert_equal expected, objects
  end

  def test_it_parses_chunked_data
    generator = Generator.new(['{"total_rows":', '0,"offset":0,"rows":[]', '}'])
    iter = YAJI::Parser.new(generator).each(['total_rows', '/rows/', '/errors/'], :with_path => true)
    begin
      loop do
        iter.next
      end
    rescue StopIteration
    end
  end

  def test_it_skips_empty_chunks
    generator = Generator.new(['{"total_rows":', '0,"offset":0,"rows":[]', '}', '', nil])
    iter = YAJI::Parser.new(generator).each(['total_rows', '/rows/', '/errors/'], :with_path => true)
    begin
      loop do
        iter.next
      end
    rescue StopIteration
    end
  end

  def test_it_correctly_handles_empty_hashes
    chunks = ['{"rows":[{"value":{}}]}']

    parser = YAJI::Parser.new(:filter => '/rows/')

    objects = []
    parser.on_object do |obj|
      objects << obj
    end

    chunks.each do |chunk|
      parser.write(chunk)
    end

    assert_equal 1, objects.size
  end

  protected

  def toys_json_str
    <<-JSON
      {
        "total_rows": 2,
        "rows": [
          {
            "id": "buzz",
            "props": {
              "humanoid": true,
              "armed": true
            },
            "movies": [1,2,3]
          },
          {
            "id": "barbie",
            "props": {
              "humanoid": true,
              "armed": false
            },
            "movies": [2,3]
          }
        ]
      }
    JSON
  end
end
